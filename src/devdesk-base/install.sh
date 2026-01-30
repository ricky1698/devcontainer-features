#!/usr/bin/env bash
set -e

echo "Installing DevDesk Base..."

# Install system packages
apt-get update
apt-get install -y \
    file \
    iputils-ping \
    stow \
    espeak \
    byacc \
    bison \
    libncurses-dev \
    libpam0g-dev

# Install supervisor if requested
if [[ "$INSTALLSUPERVISOR" == "true" ]]; then
    echo "Installing supervisor..."
    apt-get install -y supervisor
    mkdir -p /etc/supervisor/conf.d
fi

rm -rf /var/lib/apt/lists/*

# Install mise if requested
if [[ "$INSTALLMISE" == "true" ]]; then
    echo "Installing mise..."
    
    # Download and install mise
    curl -fsSL https://mise.run | sh
    
    # Setup mise for the remote user
    MISE_BIN="$_REMOTE_USER_HOME/.local/bin/mise"
    
    if [[ -f "$MISE_BIN" ]]; then
        # Add mise to shell configs
        echo 'eval "$($HOME/.local/bin/mise activate bash)"' >> "$_REMOTE_USER_HOME/.bashrc"
        echo 'eval "$($HOME/.local/bin/mise activate zsh)"' >> "$_REMOTE_USER_HOME/.zshrc"
        echo 'export PATH="$HOME/.local/share/mise/shims:$PATH"' >> "$_REMOTE_USER_HOME/.profile"
        echo 'export PATH="$HOME/.local/share/mise/shims:$PATH"' >> "$_REMOTE_USER_HOME/.bashrc"
        echo 'export PATH="$HOME/.local/share/mise/shims:$PATH"' >> "$_REMOTE_USER_HOME/.zshrc"
        
        # Add NODE_OPTIONS for IPv4/IPv6 compatibility
        echo 'export NODE_OPTIONS="--no-network-family-autoselection"' >> "$_REMOTE_USER_HOME/.profile"
        echo 'export NODE_OPTIONS="--no-network-family-autoselection"' >> "$_REMOTE_USER_HOME/.bashrc"
        echo 'export NODE_OPTIONS="--no-network-family-autoselection"' >> "$_REMOTE_USER_HOME/.zshrc"
        
        # Install packages as remote user
        if [[ -n "$PACKAGES" ]]; then
            echo "Installing mise packages: $PACKAGES"
            IFS=',' read -ra PACKAGE_ARRAY <<< "$PACKAGES"
            for package in "${PACKAGE_ARRAY[@]}"; do
                echo "Installing $package..."
                su - "$_REMOTE_USER" -c "$MISE_BIN use -g $package" || echo "Warning: Failed to install $package"
            done
        fi
        
        # Install npm global packages
        if [[ -n "$NPMGLOBALPACKAGES" ]]; then
            echo "Installing npm global packages: $NPMGLOBALPACKAGES"
            IFS=',' read -ra NPM_ARRAY <<< "$NPMGLOBALPACKAGES"
            for npm_package in "${NPM_ARRAY[@]}"; do
                echo "Installing npm package: $npm_package..."
                su - "$_REMOTE_USER" -c "$MISE_BIN exec node@lts -- npm install -g $npm_package" || echo "Warning: Failed to install $npm_package"
            done
        fi
        
        # Fix ownership
        chown -R "$_REMOTE_USER:$_REMOTE_USER" "$_REMOTE_USER_HOME/.local" 2>/dev/null || true
    else
        echo "Warning: mise binary not found at $MISE_BIN"
    fi
fi

echo "DevDesk Base installation complete!"
