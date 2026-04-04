#!/usr/bin/env bash
set -e

echo "Installing T3Code..."

# Install t3 globally via mise npm
MISE_BIN="$_REMOTE_USER_HOME/.local/bin/mise"
su - "$_REMOTE_USER" -c "$MISE_BIN exec node@lts -- npm install -g t3"

# Ensure supervisor config directory exists
mkdir -p /etc/supervisor/conf.d

# Create supervisor config
AUTOSTART_VALUE="false"
if [[ "$AUTOSTART" == "true" ]]; then
    AUTOSTART_VALUE="true"
fi

cat > /etc/supervisor/conf.d/t3code.conf << CONFEOF
[program:t3code]
command=$_REMOTE_USER_HOME/.local/share/mise/shims/t3 --host $HOSTNAME --no-browser
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=5
autorestart=true
startretries=3
stderr_logfile=/var/log/t3code.err.log
stdout_logfile=/var/log/t3code.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME",NODE_OPTIONS="--no-network-family-autoselection"
CONFEOF

# Create entrypoint script
cat > /usr/local/bin/devdesk-t3code-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Reload supervisor to pick up t3code config
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start t3code 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-t3code-entrypoint

echo "T3Code installation complete!"
