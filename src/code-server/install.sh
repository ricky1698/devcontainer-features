#!/usr/bin/env bash
set -e

echo "Installing Code Server..."

# Install code-server
CODE_SERVER_INSTALL_ARGS=""
if [[ -n "$VERSION" ]]; then
    CODE_SERVER_INSTALL_ARGS="--version=$VERSION"
fi

curl -fsSL https://code-server.dev/install.sh | sh -s -- $CODE_SERVER_INSTALL_ARGS

# Install extensions
if [[ -n "$EXTENSIONS" ]]; then
    IFS=',' read -ra EXT_ARRAY <<< "$EXTENSIONS"
    for ext in "${EXT_ARRAY[@]}"; do
        echo "Installing extension: $ext"
        code-server --install-extension "$ext" || echo "Warning: Failed to install $ext"
    done
fi

# Ensure supervisor config directory exists
mkdir -p /etc/supervisor/conf.d

# Create supervisor config
cat > /etc/supervisor/conf.d/code-server.conf << CONFEOF
[program:code-server]
command=/usr/bin/code-server --auth $AUTH --bind-addr $HOST:$PORT $_REMOTE_USER_HOME
directory=$_REMOTE_USER_HOME
autostart=true
startsecs=5
autorestart=true
startretries=3
stderr_logfile=/var/log/code-server.err.log
stdout_logfile=/var/log/code-server.log
user=$_REMOTE_USER
environment=HOME="$_REMOTE_USER_HOME"
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
