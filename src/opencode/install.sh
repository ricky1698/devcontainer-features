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
stderr_logfile=/var/log/opencode.err.log
stdout_logfile=/var/log/opencode.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME"
CONFEOF

echo "OpenCode installation complete!"
echo "Start with: supervisorctl start opencode"
