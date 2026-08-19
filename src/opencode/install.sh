#!/usr/bin/env bash
set -e

echo "Installing OpenCode..."

# Ensure supervisor config directory exists
mkdir -p /etc/supervisor/conf.d

# Create supervisor config
AUTOSTART_VALUE="false"
if [[ "$AUTOSTART" == "true" ]]; then
    AUTOSTART_VALUE="true"
fi

cat > /etc/supervisor/conf.d/opencode.conf << CONFEOF
[program:opencode]
command=$_REMOTE_USER_HOME/.local/share/mise/shims/bunx opencode-ai serve --hostname $HOSTNAME
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=5
autorestart=true
startretries=3
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/opencode.err.log
stdout_logfile=/var/log/opencode.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME"
CONFEOF

# Create entrypoint script
cat > /usr/local/bin/devdesk-opencode-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Reload supervisor to pick up opencode config
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start opencode 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-opencode-entrypoint

echo "OpenCode installation complete!"
