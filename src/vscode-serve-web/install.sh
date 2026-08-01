#!/usr/bin/env bash
set -e

echo "Installing VS Code Serve Web..."

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  CLI_ARCH="x64" ;;
    aarch64|arm64) CLI_ARCH="arm64" ;;
    armv7l)  CLI_ARCH="armhf" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Download the official VS Code CLI binary
CLI_URL="https://update.code.visualstudio.com/latest/cli-linux-${CLI_ARCH}/stable"
echo "Downloading VS Code CLI (${CLI_ARCH})..."
curl -fsSL "$CLI_URL" | tar -xz -C /tmp
mv /tmp/code /usr/local/bin/code
chmod +x /usr/local/bin/code
echo "VS Code CLI installed at /usr/local/bin/code"

# Pre-download the VS Code Server by briefly starting serve-web.
# The CLI automatically downloads the matching server bundle on first run.
echo "Pre-downloading VS Code Server (this may take a while)..."
su - "$_REMOTE_USER" -c "
    /usr/local/bin/code serve-web \
        --host 127.0.0.1 \
        --port 19877 \
        --without-connection-token \
        --accept-server-license-terms \
        > /tmp/vscode-serve-web-predown.log 2>&1 &
    VSCODE_PID=\$!

    # Wait until the server directory appears (up to 120 s)
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

# Install extensions using the downloaded server binary
if [[ -n "$EXTENSIONS" ]]; then
    SERVER_CODE_BIN=$(find "$_REMOTE_USER_HOME/.vscode/cli/servers" -name 'code-server' -type f 2>/dev/null | head -1)
    if [[ -z "$SERVER_CODE_BIN" ]]; then
        echo "Warning: VS Code Server binary not found — skipping extension installation"
    else
        echo "Using server binary: $SERVER_CODE_BIN"
        IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
        for ext in "${EXT_ARRAY[@]}"; do
            ext="$(echo "$ext" | xargs)"  # trim whitespace
            [[ -z "$ext" ]] && continue
            echo "Installing extension: $ext"
            su - "$_REMOTE_USER" -c "'$SERVER_CODE_BIN' --install-extension '$ext'" \
                || echo "Warning: Failed to install $ext"
        done
    fi
fi

# Determine token flag
if [[ "$CONNECTION_TOKEN" == "false" ]]; then
    TOKEN_FLAG="--without-connection-token"
else
    TOKEN_FLAG=""
fi

# Determine base path flag
if [[ -n "$SERVER_BASE_PATH" ]]; then
    BASE_PATH_FLAG="--server-base-path $SERVER_BASE_PATH"
else
    BASE_PATH_FLAG=""
fi

# Create supervisor config
mkdir -p /etc/supervisor/conf.d
cat > /etc/supervisor/conf.d/vscode-serve-web.conf << CONFEOF
[program:vscode-serve-web]
command=/usr/local/bin/code serve-web --host $HOST --port $PORT $TOKEN_FLAG $BASE_PATH_FLAG --accept-server-license-terms
directory=$_REMOTE_USER_HOME
autostart=true
startsecs=10
autorestart=true
startretries=3
; signal the whole process group, else children orphan to PID 1 and keep holding ports
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/vscode-serve-web.err.log
stdout_logfile=/var/log/vscode-serve-web.log
user=$_REMOTE_USER
environment=HOME="$_REMOTE_USER_HOME"
CONFEOF

# Create entrypoint script
cat > /usr/local/bin/devdesk-vscode-serve-web-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Pick up vscode-serve-web config and start it
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start vscode-serve-web 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-vscode-serve-web-entrypoint

echo "VS Code Serve Web installation complete!"
