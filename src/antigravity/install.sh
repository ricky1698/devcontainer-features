#!/usr/bin/env bash
set -e

echo "Installing Antigravity Remote Control..."

if [[ -z "${_REMOTE_USER:-}" || -z "${_REMOTE_USER_HOME:-}" ]]; then
    echo "ERROR: _REMOTE_USER / _REMOTE_USER_HOME not set — is devcontainers/common-utils applied?"
    exit 1
fi

# --- 1. System dependencies ------------------------------------------------
apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl procps
rm -rf /var/lib/apt/lists/*

# --- 2. Install the agy CLI -------------------------------------------------
# The official installer resolves the platform manifest, verifies a sha512, and
# drops a ~200 MB static binary into $HOME/.local/bin. Run it as the remote user
# so agy can rewrite itself when it self-updates.
AGY_BIN="$_REMOTE_USER_HOME/.local/bin/agy"
if [[ -x "$AGY_BIN" ]]; then
    echo "agy already present at $AGY_BIN — skipping download"
else
    su - "$_REMOTE_USER" -c "curl -fsSL https://antigravity.google/cli/install.sh | bash"
fi

if [[ ! -x "$AGY_BIN" ]]; then
    echo "ERROR: agy installation failed — $AGY_BIN not found."
    exit 1
fi
echo "agy installed at $AGY_BIN"

# --- 3. Launcher wrapper ---------------------------------------------------
# Same job as the wrapper agy-daemon.sh writes into ~/.antigravity/bin, but kept
# outside $HOME so a mounted home volume can't shadow it. Tunables come from the
# supervisor config's environment= line.
cat > /usr/local/bin/agy-remote-control <<'WRAPPEREOF'
#!/bin/bash
set -u

# supervisor hands the program a pipe on stdin and never writes to or closes it,
# so agy blocks forever on its first read. systemd gave the unit /dev/null, which
# reads as EOF; restore that here or the daemon never finishes starting.
exec 0</dev/null

AGY_BIN="${HOME}/.local/bin/agy"
[[ -x "$AGY_BIN" ]] || AGY_BIN="$(command -v agy || true)"
if [[ -z "$AGY_BIN" || ! -x "$AGY_BIN" ]]; then
    echo "agy-remote-control: 'agy' not found in ${HOME}/.local/bin or on PATH" >&2
    exit 127
fi

# systemd ran this as 'ExecStartPre=-agy --bg-updater'. supervisor has no
# pre-start hook, so it happens here — best effort, and time-boxed so a hung
# update check can never hold the daemon down.
if [[ "${AGY_CLI_DISABLE_AUTO_UPDATE:-false}" != "true" ]]; then
    timeout 60 "$AGY_BIN" --bg-updater || true
fi

# The CLI exits at startup if its hub port is taken, so probe for a free one on
# every launch (supervisor restarts this wrapper, re-picking a port).
PORT="${AGY_HUB_PORT_START:-4400}"
PORT_MAX=$(( PORT + 100 ))
while (( PORT < PORT_MAX )) && (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null; do
    PORT=$(( PORT + 1 ))
done

if [[ -n "${AGY_REMOTE_CONTROL_NAME:-}" ]]; then
    exec "$AGY_BIN" --remote-control --hub-port "$PORT" \
        --remote-control-name "$AGY_REMOTE_CONTROL_NAME" "$@"
fi
exec "$AGY_BIN" --remote-control --hub-port "$PORT" "$@"
WRAPPEREOF
chmod +x /usr/local/bin/agy-remote-control

# --- 4. One-time sign-in helper --------------------------------------------
# The daemon has no stdin, so the paste-a-code login can't run under supervisor.
# Do it once here; the token lands in ~/.gemini and the daemon reuses it.
cat > /usr/local/bin/agy-remote-control-login <<'LOGINEOF'
#!/bin/bash
set -u

TOKEN_FILE="${HOME}/.gemini/jetski-standalone-oauth-token"

if [[ -s "$TOKEN_FILE" ]]; then
    echo "Already signed in ($TOKEN_FILE). Delete that file to sign in again."
else
    if [[ ! -t 0 ]]; then
        echo "Sign-in needs an interactive terminal." >&2
        exit 1
    fi
    echo "--------------------------------------------------------------"
    echo "One-time sign-in. Open the URL printed below and paste the code"
    echo "back if prompted. This exits by itself once the token appears."
    echo "--------------------------------------------------------------"
    # Watchdog: stop the interactive CLI as soon as the token file shows up.
    ( while [[ ! -s "$TOKEN_FILE" ]]; do sleep 2; done; sleep 2
      pkill -P $$ -f -- "--remote-control" 2>/dev/null ) &
    watchdog=$!
    trap 'echo' INT
    /usr/local/bin/agy-remote-control >/dev/null || true
    trap - INT
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true

    if [[ ! -s "$TOKEN_FILE" ]]; then
        echo "Sign-in did not complete — no auth token written." >&2
        exit 1
    fi
    echo "Signed in."
fi

sudo supervisorctl start antigravity 2>/dev/null || true
sudo supervisorctl status antigravity 2>/dev/null || true
LOGINEOF
chmod +x /usr/local/bin/agy-remote-control-login

# --- 5. Supervisor config --------------------------------------------------
mkdir -p /etc/supervisor/conf.d

AUTOSTART_VALUE="false"
[[ "$AUTOSTART" == "true" ]] && AUTOSTART_VALUE="true"

# Mirrors the unit's Environment=AGY_CLI_DISABLE_AUTO_UPDATE=false.
DISABLE_AUTO_UPDATE="true"
[[ "$AUTOUPDATE" == "true" ]] && DISABLE_AUTO_UPDATE="false"

SUPERVISOR_SHELL="$(command -v zsh || true)"
[ -x "$SUPERVISOR_SHELL" ] || SUPERVISOR_SHELL="/bin/bash"
echo "Using SHELL=$SUPERVISOR_SHELL for supervisor-managed processes"

cat > /etc/supervisor/conf.d/antigravity.conf <<CONFEOF
[program:antigravity]
command=/usr/local/bin/agy-remote-control
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=5
autorestart=true
startretries=3
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/antigravity.err.log
stdout_logfile=/var/log/antigravity.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME",USER="$_REMOTE_USER",LOGNAME="$_REMOTE_USER",SHELL="$SUPERVISOR_SHELL",AGY_CLI_DISABLE_AUTO_UPDATE="$DISABLE_AUTO_UPDATE",AGY_REMOTE_CONTROL_NAME="$INSTANCENAME",AGY_HUB_PORT_START="4400"
CONFEOF

# --- 6. Entrypoint hook ----------------------------------------------------
cat > /usr/local/bin/devdesk-antigravity-entrypoint <<'ENTRYPOINTEOF'
#!/bin/bash

if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true

if [[ -s "$HOME/.gemini/jetski-standalone-oauth-token" ]]; then
    sudo supervisorctl start antigravity 2>/dev/null || true
else
    echo "antigravity: not signed in — daemon not started. Run 'agy-remote-control-login' once."
fi

exec "$@"
ENTRYPOINTEOF
chmod +x /usr/local/bin/devdesk-antigravity-entrypoint

echo "Antigravity Remote Control installation complete!"
