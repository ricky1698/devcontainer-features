#!/usr/bin/env bash
set -e

echo "Installing Code Server..."

# Install code-server
CODE_SERVER_INSTALL_ARGS=""
if [[ -n "$VERSION" ]]; then
    CODE_SERVER_INSTALL_ARGS="--version=$VERSION"
fi

curl -fsSL https://code-server.dev/install.sh | sh -s -- $CODE_SERVER_INSTALL_ARGS

# Install GitHub Copilot Chat extension from VSIX (always installed)
if [[ -z "$COPILOT_CHAT_VERSION" ]]; then
    echo "Fetching latest GitHub Copilot Chat version..."
    COPILOT_CHAT_VERSION=$(curl -fsSL https://api.github.com/repos/microsoft/vscode-copilot-chat/releases/latest | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
    echo "Latest version: ${COPILOT_CHAT_VERSION}"
fi
VSIX_URL="https://github.com/microsoft/vscode-copilot-chat/releases/download/v${COPILOT_CHAT_VERSION}/GitHub.copilot-chat.${COPILOT_CHAT_VERSION}.universal.vsix"
VSIX_FILE="/tmp/GitHub.copilot-chat.${COPILOT_CHAT_VERSION}.universal.vsix"
echo "Downloading GitHub Copilot Chat v${COPILOT_CHAT_VERSION}..."
curl -fsSL -o "$VSIX_FILE" "$VSIX_URL"
chmod 644 "$VSIX_FILE"
echo "Installing GitHub Copilot Chat extension as ${_REMOTE_USER}..."
su - "$_REMOTE_USER" -c "code-server --install-extension '$VSIX_FILE'" || echo "Warning: Failed to install GitHub Copilot Chat"
rm -f "$VSIX_FILE"

# Install extensions
if [[ -n "$EXTENSIONS" ]]; then
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for ext in "${EXT_ARRAY[@]}"; do
        echo "Installing extension: $ext"
        su - "$_REMOTE_USER" -c "code-server --install-extension '$ext'" || echo "Warning: Failed to install $ext"
    done
fi

# Ensure supervisor config directory exists
mkdir -p /etc/supervisor/conf.d

# Create supervisor config
SUPERVISOR_SHELL="$(command -v zsh || true)"
[ -x "$SUPERVISOR_SHELL" ] || SUPERVISOR_SHELL="/bin/bash"

cat > /etc/supervisor/conf.d/code-server.conf << CONFEOF
[program:code-server]
command=/usr/bin/code-server --auth $AUTH --bind-addr $HOST:$PORT $_REMOTE_USER_HOME
directory=$_REMOTE_USER_HOME
autostart=true
startsecs=5
autorestart=true
startretries=3
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/code-server.err.log
stdout_logfile=/var/log/code-server.log
user=$_REMOTE_USER
environment=HOME="$_REMOTE_USER_HOME",SHELL="$SUPERVISOR_SHELL"
CONFEOF

# Create entrypoint script
cat > /usr/local/bin/devdesk-code-server-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Reload supervisor to pick up code-server config
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start code-server 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-code-server-entrypoint

echo "Code Server installation complete!"
