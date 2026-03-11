#!/usr/bin/env bash
set -e

echo "Installing OpenClaw..."

# Install openclaw via official installer
curl -fsSL https://openclaw.ai/install.sh | bash

# Ensure supervisor config directory exists
mkdir -p /etc/supervisor/conf.d

# Create supervisor config
AUTOSTART_VALUE="false"
if [[ "$AUTOSTART" == "true" ]]; then
    AUTOSTART_VALUE="true"
fi

cat > /etc/supervisor/conf.d/clawdbot.conf << CONFEOF
[program:clawdbot]
command=/usr/local/bin/mise exec node@lts -- openclaw gateway
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=5
autorestart=true
startretries=3
stderr_logfile=/var/log/clawdbot.err.log
stdout_logfile=/var/log/clawdbot.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME",NODE_OPTIONS="--no-network-family-autoselection"
CONFEOF

# Create entrypoint script
cat > /usr/local/bin/devdesk-openclaw-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Reload supervisor to pick up clawdbot config
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start clawdbot 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-openclaw-entrypoint

echo "OpenClaw installation complete!"
