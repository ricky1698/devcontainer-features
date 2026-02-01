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

# Create entrypoint script
cat > /usr/local/bin/devdesk-tailscale-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

echo "→ [tailscale-setup] Entrypoint starting..."

# Source profile.d scripts for environment variables
if [ -f /etc/profile.d/devdesk-tailscale.sh ]; then
    source /etc/profile.d/devdesk-tailscale.sh
fi

# Debug: check if TS_OAUTH_TOKEN is set
if [ -n "${TS_OAUTH_TOKEN}" ]; then
    echo "→ [tailscale-setup] TS_OAUTH_TOKEN is set"
else
    echo "→ [tailscale-setup] TS_OAUTH_TOKEN is NOT set"
fi

# Fallback: start tailscaled if not running (entrypoint chain may be broken by other features)
if ! pgrep -x tailscaled > /dev/null; then
    echo "→ [tailscale-setup] tailscaled not running, starting..."
    if command -v tailscaled-devcontainer-start &> /dev/null; then
        sudo /usr/local/sbin/tailscaled-devcontainer-start
    fi
else
    echo "→ [tailscale-setup] tailscaled already running"
fi

# Run Tailscale setup
if command -v devdesk-tailscale-setup &> /dev/null; then
    echo "→ [tailscale-setup] Running devdesk-tailscale-setup..."
    devdesk-tailscale-setup
fi

echo "→ [tailscale-setup] Entrypoint done"

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-tailscale-entrypoint

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
