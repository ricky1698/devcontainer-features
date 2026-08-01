#!/usr/bin/env bash
set -e

echo "Installing OpenAB Gateway..."

if [[ -z "${_REMOTE_USER:-}" || -z "${_REMOTE_USER_HOME:-}" ]]; then
    echo "ERROR: _REMOTE_USER / _REMOTE_USER_HOME not set — is devcontainers/common-utils applied?"
    exit 1
fi

# --- 1. System dependencies ------------------------------------------------
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl git procps
rm -rf /var/lib/apt/lists/*

# --- 2. Locate cargo (from devdesk-base) -----------------------------------
CARGO_BIN="$_REMOTE_USER_HOME/.local/share/mise/shims/cargo"
if [[ ! -x "$CARGO_BIN" ]]; then
    CARGO_BIN="$_REMOTE_USER_HOME/.cargo/bin/cargo"
fi
if [[ ! -x "$CARGO_BIN" ]]; then
    echo "ERROR: cargo not found. Install rust via devdesk-base 'packages' option (e.g. rust@latest)."
    exit 1
fi

# --- 3. Build openab-gateway from source -----------------------------------
# Resolve version → git ref (same semantics as openab-broker):
#   'latest'      → main branch
#   '0.7.6' etc.  → tag v0.7.6 (auto-prepend 'v' to semver-looking values)
#   anything else → used verbatim as a git ref (branch / tag / SHA)
if [[ "$VERSION" == "latest" ]]; then
    OPENAB_REF="main"
elif [[ "$VERSION" =~ ^[0-9] ]]; then
    OPENAB_REF="v$VERSION"
else
    OPENAB_REF="$VERSION"
fi

echo "Cloning openab (version='${VERSION}' → ref='${OPENAB_REF}') from ${REPOURL}..."
BUILD_DIR=$(mktemp -d)
chown "$_REMOTE_USER:$_REMOTE_USER" "$BUILD_DIR"
su - "$_REMOTE_USER" -c "
    set -e
    cd '$BUILD_DIR'
    git clone '$REPOURL' src
    cd src
    git checkout '$OPENAB_REF'
    if [[ ! -d gateway ]]; then
        echo 'ERROR: gateway/ sub-crate not found at ref $OPENAB_REF — does this version include the gateway crate?'
        exit 1
    fi
    cd gateway
    echo 'Building openab-gateway (release) — this may take several minutes...'
    '$CARGO_BIN' build --release
"
install -m 0755 "$BUILD_DIR/src/gateway/target/release/openab-gateway" /usr/local/bin/openab-gateway
rm -rf "$BUILD_DIR"
echo "openab-gateway binary installed at /usr/local/bin/openab-gateway"

# --- 4. Supervisor config --------------------------------------------------
# openab-gateway is driven entirely by environment variables (no config file).
# Platform credentials must be set in the container environment before
# supervisor starts the program — see README for the full list.
mkdir -p /etc/supervisor/conf.d
AUTOSTART_VALUE="false"
[[ "$AUTOSTART" == "true" ]] && AUTOSTART_VALUE="true"

cat > /etc/supervisor/conf.d/openab-gateway.conf <<SUPEOF
[program:openab-gateway]
command=/usr/local/bin/openab-gateway
directory=${_REMOTE_USER_HOME}
autostart=${AUTOSTART_VALUE}
startsecs=5
autorestart=true
startretries=3
; signal the whole process group, else children orphan to PID 1 and keep holding ports
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/openab-gateway.err.log
stdout_logfile=/var/log/openab-gateway.log
user=${_REMOTE_USER}
environment=PATH="${_REMOTE_USER_HOME}/.local/bin:${_REMOTE_USER_HOME}/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="${_REMOTE_USER_HOME}",GATEWAY_LISTEN="${LISTENADDR}"
SUPEOF

# --- 5. Entrypoint hook ----------------------------------------------------
cat > /usr/local/bin/devdesk-openab-gateway-entrypoint <<'ENTRYPOINTEOF'
#!/bin/bash

if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true

# Auto-start the gateway if at least one platform credential is present.
# Without any credential the gateway boots but does nothing useful, so we
# skip starting it to keep `supervisorctl status` quiet for users who only
# want the broker.
if [[ -n "$TELEGRAM_BOT_TOKEN" ]] \
    || [[ -n "$FEISHU_APP_ID" ]] \
    || [[ -n "$LINE_CHANNEL_SECRET" ]] \
    || [[ "$GOOGLE_CHAT_ENABLED" == "true" || "$GOOGLE_CHAT_ENABLED" == "1" ]]; then
    sudo supervisorctl start openab-gateway 2>/dev/null || true
else
    echo "openab-gateway: no platform credentials set (TELEGRAM_BOT_TOKEN / FEISHU_APP_ID / LINE_CHANNEL_SECRET / GOOGLE_CHAT_ENABLED) — gateway not started."
fi

exec "$@"
ENTRYPOINTEOF
chmod +x /usr/local/bin/devdesk-openab-gateway-entrypoint

echo "OpenAB Gateway installation complete!"
