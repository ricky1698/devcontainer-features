#!/usr/bin/env bash
# setup.sh — standalone installer for vscode-serve-web
# Run this inside an already-running devcontainer (requires sudo).
#
# Usage:
#   bash setup.sh [--port 8888] [--host 0.0.0.0] [--with-token] [--user vscode] [--extensions "ms-python.python,eamodio.gitlens"]
#
set -e

# ---------- defaults ----------
PORT=8888
HOST=0.0.0.0
CONNECTION_TOKEN=false
EXTENSIONS=""
EXPLICIT_USER=""

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)        PORT="$2";         shift 2 ;;
        --host)        HOST="$2";         shift 2 ;;
        --with-token)  CONNECTION_TOKEN=true; shift ;;
        --extensions)  EXTENSIONS="$2";   shift 2 ;;
        --user)        EXPLICIT_USER="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------- resolve target user ----------
if [[ -n "$EXPLICIT_USER" ]]; then
    REMOTE_USER="$EXPLICIT_USER"
elif [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
    # invoked via: sudo bash setup.sh
    REMOTE_USER="$SUDO_USER"
elif [[ "$(whoami)" != "root" ]]; then
    # running as a normal user without sudo
    REMOTE_USER="$(whoami)"
else
    # running as root — try common devcontainer usernames
    for candidate in vscode codespace ubuntu debian user; do
        if id "$candidate" &>/dev/null; then
            REMOTE_USER="$candidate"
            break
        fi
    done
    if [[ -z "$REMOTE_USER" ]]; then
        echo "ERROR: Could not detect a non-root user. Pass --user <username> explicitly."
        exit 1
    fi
fi

REMOTE_USER_HOME=$(getent passwd "$REMOTE_USER" | cut -d: -f6)

echo "==> vscode-serve-web setup"
echo "    user:       $REMOTE_USER ($REMOTE_USER_HOME)"
echo "    listen:     $HOST:$PORT"
echo "    token:      $CONNECTION_TOKEN"
echo "    extensions: ${EXTENSIONS:-none}"
echo ""

# ---------- 1. install supervisor if missing ----------
if ! command -v supervisord &>/dev/null; then
    echo "==> Installing supervisor..."
    apt-get update -qq
    apt-get install -y supervisor
    mkdir -p /etc/supervisor/conf.d
fi

# ---------- 2. download VS Code CLI ----------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)        CLI_ARCH="x64" ;;
    aarch64|arm64) CLI_ARCH="arm64" ;;
    armv7l)        CLI_ARCH="armhf" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

if command -v code &>/dev/null; then
    echo "==> VS Code CLI already installed, skipping download"
else
    CLI_URL="https://update.code.visualstudio.com/latest/cli-linux-${CLI_ARCH}/stable"
    echo "==> Downloading VS Code CLI (${CLI_ARCH})..."
    curl -fsSL "$CLI_URL" | tar -xz -C /tmp
    mv /tmp/code /usr/local/bin/code
    chmod +x /usr/local/bin/code
fi

# ---------- 3. pre-download VS Code Server ----------
echo "==> Pre-downloading VS Code Server (may take a while)..."
su - "$REMOTE_USER" -c "
    /usr/local/bin/code serve-web \
        --host 127.0.0.1 \
        --port 19877 \
        --without-connection-token \
        --accept-server-license-terms \
        > /tmp/vscode-serve-web-predown.log 2>&1 &
    VSCODE_PID=\$!

    for i in \$(seq 1 120); do
        if find \"\$HOME/.vscode/cli/servers\" -name 'code-server' -type f 2>/dev/null | grep -q .; then
            echo 'VS Code Server downloaded.'
            break
        fi
        sleep 1
    done

    kill \$VSCODE_PID 2>/dev/null || true
    wait \$VSCODE_PID 2>/dev/null || true
" || echo "Warning: pre-download step encountered an issue (non-fatal)"

# ---------- 4. install extensions ----------
if [[ -n "$EXTENSIONS" ]]; then
    SERVER_CODE_BIN=$(find "$REMOTE_USER_HOME/.vscode/cli/servers" -name 'code-server' -type f 2>/dev/null | head -1)
    if [[ -z "$SERVER_CODE_BIN" ]]; then
        echo "Warning: VS Code Server binary not found — skipping extension installation"
    else
        IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
        for ext in "${EXT_ARRAY[@]}"; do
            ext="$(echo "$ext" | xargs)"
            [[ -z "$ext" ]] && continue
            echo "==> Installing extension: $ext"
            su - "$REMOTE_USER" -c "'$SERVER_CODE_BIN' --install-extension '$ext'" \
                || echo "Warning: Failed to install $ext"
        done
    fi
fi

# ---------- 5. supervisor config ----------
if [[ "$CONNECTION_TOKEN" == "false" ]]; then
    TOKEN_FLAG="--without-connection-token"
else
    TOKEN_FLAG=""
fi

cat > /etc/supervisor/conf.d/vscode-serve-web.conf << CONFEOF
[program:vscode-serve-web]
command=/usr/local/bin/code serve-web --host $HOST --port $PORT $TOKEN_FLAG --accept-server-license-terms
directory=$REMOTE_USER_HOME
autostart=true
startsecs=10
autorestart=true
startretries=3
stderr_logfile=/var/log/vscode-serve-web.err.log
stdout_logfile=/var/log/vscode-serve-web.log
user=$REMOTE_USER
environment=HOME="$REMOTE_USER_HOME"
CONFEOF

# ---------- 6. start / restart service ----------
if pgrep -x supervisord > /dev/null; then
    supervisorctl reread
    supervisorctl update
    supervisorctl restart vscode-serve-web 2>/dev/null || supervisorctl start vscode-serve-web
else
    supervisord -c /etc/supervisor/supervisord.conf
    sleep 2
    supervisorctl start vscode-serve-web
fi

echo ""
echo "==> Done! VS Code is available at http://localhost:${PORT}"
