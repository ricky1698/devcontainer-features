#!/usr/bin/env bash
set -e

echo "Installing VibeTunnel..."

# Ensure supervisor config directory exists
mkdir -p /etc/supervisor/conf.d

# Create supervisor config
AUTOSTART_VALUE="false"
if [[ "$AUTOSTART" == "true" ]]; then
    AUTOSTART_VALUE="true"
fi

NOAUTH_FLAG=""
if [[ "$NOAUTH" == "true" ]]; then
    NOAUTH_FLAG="--no-auth"
fi

SUPERVISOR_SHELL="$(command -v zsh || true)"
[ -x "$SUPERVISOR_SHELL" ] || SUPERVISOR_SHELL="/bin/bash"

cat > /etc/supervisor/conf.d/vibetunnel.conf << CONFEOF
[program:vibetunnel]
command=$_REMOTE_USER_HOME/.local/share/mise/shims/vibetunnel $NOAUTH_FLAG
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=5
autorestart=true
startretries=3
stopasgroup=true
killasgroup=true
stderr_logfile=/var/log/vibetunnel.err.log
stdout_logfile=/var/log/vibetunnel.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME",SHELL="$SUPERVISOR_SHELL"
CONFEOF

# Create entrypoint script
cat > /usr/local/bin/devdesk-vibetunnel-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Reload supervisor to pick up vibetunnel config
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start vibetunnel 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-vibetunnel-entrypoint

echo "VibeTunnel installation complete!"
