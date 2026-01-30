#!/usr/bin/env bash
set -e

echo "Installing Tailscale Auto-Setup..."

# Create the setup script
mkdir -p /usr/local/bin

cat > /usr/local/bin/devdesk-tailscale-setup << 'SCRIPTEOF'
#!/bin/bash

# Setup Tailscale if TS_OAUTH_TOKEN is set
if [ -n "${TS_OAUTH_TOKEN}" ]; then
    echo "→ Setting up Tailscale with OAuth token..."
    
    # Get workspace name from current directory or use hostname
    if [ -n "${WORKSPACE_NAME}" ]; then
        ROOT_DIR="${WORKSPACE_NAME}"
    else
        ROOT_DIR=$(basename "$(pwd)")
    fi
    
    MACHINE_HOSTNAME=$(hostname)
    TS_HOSTNAME="${ROOT_DIR}-${MACHINE_HOSTNAME}"
    
    echo "→ Using Tailscale hostname: ${TS_HOSTNAME}"
    
    TAILSCALE_ARGS="--authkey=${TS_OAUTH_TOKEN} --reset --hostname=${TS_HOSTNAME}"
    
    if [ "${TAILSCALE_ACCEPT_ROUTES}" = "true" ]; then
        TAILSCALE_ARGS="${TAILSCALE_ARGS} --accept-routes"
    fi
    
    if [ "${TAILSCALE_SSH}" = "true" ]; then
        TAILSCALE_ARGS="${TAILSCALE_ARGS} --ssh"
    fi
    
    sudo tailscale up ${TAILSCALE_ARGS}
    echo "→ Tailscale setup complete"
else
    echo "→ TS_OAUTH_TOKEN not set, skipping Tailscale setup"
fi
SCRIPTEOF

chmod +x /usr/local/bin/devdesk-tailscale-setup

# Set environment variables for the script
if [[ "$AUTOCONNECT" == "true" ]]; then
    echo "export TAILSCALE_AUTO_CONNECT=true" >> /etc/profile.d/devdesk-tailscale.sh
fi

if [[ "$ENABLESSH" == "true" ]]; then
    echo "export TAILSCALE_SSH=true" >> /etc/profile.d/devdesk-tailscale.sh
fi

if [[ "$ACCEPTROUTES" == "true" ]]; then
    echo "export TAILSCALE_ACCEPT_ROUTES=true" >> /etc/profile.d/devdesk-tailscale.sh
fi

chmod +x /etc/profile.d/devdesk-tailscale.sh 2>/dev/null || true

echo "Tailscale Auto-Setup installation complete!"
echo "Run 'devdesk-tailscale-setup' to connect (requires TS_OAUTH_TOKEN env var)"
