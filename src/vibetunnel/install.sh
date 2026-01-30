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

cat > /etc/supervisor/conf.d/vibetunnel.conf << CONFEOF
[program:vibetunnel]
command=$_REMOTE_USER_HOME/.local/share/mise/shims/vibetunnel $NOAUTH_FLAG
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=5
autorestart=true
startretries=3
stderr_logfile=/var/log/vibetunnel.err.log
stdout_logfile=/var/log/vibetunnel.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME"
CONFEOF

echo "VibeTunnel installation complete!"
echo "Start with: supervisorctl start vibetunnel"
