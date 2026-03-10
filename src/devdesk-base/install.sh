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

    # Setup mise path for the remote user
    MISE_BIN="$_REMOTE_USER_HOME/.local/bin/mise"

    # Ensure the directory exists
    mkdir -p "$(dirname "$MISE_BIN")"

    # Download and install mise to the correct location (not /root)
    # Export so the pipe subshell inherits it
    export MISE_INSTALL_PATH="$MISE_BIN"
    curl -fsSL https://mise.run | sh

    # Fix ownership of the .local directory
    chown -R "$_REMOTE_USER:$_REMOTE_USER" "$_REMOTE_USER_HOME/.local"
    
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
        
        # Install mise packages (defaults + extra)
        ALL_PACKAGES=""
        [[ -n "$PACKAGES" ]] && ALL_PACKAGES="$PACKAGES"
        [[ -n "$EXTRAPACKAGES" ]] && ALL_PACKAGES="${ALL_PACKAGES:+$ALL_PACKAGES,}$EXTRAPACKAGES"

        if [[ -n "$ALL_PACKAGES" ]]; then
            echo "Installing mise packages: $ALL_PACKAGES"
            IFS=',' read -ra PACKAGE_ARRAY <<< "$ALL_PACKAGES"
            for package in "${PACKAGE_ARRAY[@]}"; do
                echo "Installing $package..."
                su - "$_REMOTE_USER" -c "$MISE_BIN use -g $package" || echo "Warning: Failed to install $package"
            done
        fi

        # Install npm global packages (defaults + extra)
        ALL_NPM_PACKAGES=""
        [[ -n "$NPMGLOBALPACKAGES" ]] && ALL_NPM_PACKAGES="$NPMGLOBALPACKAGES"
        [[ -n "$EXTRANPMGLOBALPACKAGES" ]] && ALL_NPM_PACKAGES="${ALL_NPM_PACKAGES:+$ALL_NPM_PACKAGES,}$EXTRANPMGLOBALPACKAGES"

        if [[ -n "$ALL_NPM_PACKAGES" ]]; then
            echo "Installing npm global packages: $ALL_NPM_PACKAGES"
            IFS=',' read -ra NPM_ARRAY <<< "$ALL_NPM_PACKAGES"
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

# Install cargo packages (defaults + extra)
ALL_CARGO_PACKAGES=""
[[ -n "$CARGOPACKAGES" ]] && ALL_CARGO_PACKAGES="$CARGOPACKAGES"
[[ -n "$EXTRACARGOPACKAGES" ]] && ALL_CARGO_PACKAGES="${ALL_CARGO_PACKAGES:+$ALL_CARGO_PACKAGES,}$EXTRACARGOPACKAGES"

if [[ -n "$ALL_CARGO_PACKAGES" ]]; then
    echo "Installing cargo packages: $ALL_CARGO_PACKAGES"

    # Find cargo: mise shims first, then ~/.cargo/bin
    CARGO_BIN="$_REMOTE_USER_HOME/.local/share/mise/shims/cargo"
    if [[ ! -x "$CARGO_BIN" ]]; then
        CARGO_BIN="$_REMOTE_USER_HOME/.cargo/bin/cargo"
    fi

    if [[ ! -x "$CARGO_BIN" ]]; then
        echo "Warning: cargo not found, skipping cargo packages. Install rust via mise packages option first."
    else
        IFS=',' read -ra CARGO_ARRAY <<< "$ALL_CARGO_PACKAGES"
        for pkg in "${CARGO_ARRAY[@]}"; do
            echo "Installing cargo package: $pkg..."
            su - "$_REMOTE_USER" -c "$CARGO_BIN install $pkg" || echo "Warning: Failed to install cargo package $pkg"
        done
        chown -R "$_REMOTE_USER:$_REMOTE_USER" "$_REMOTE_USER_HOME/.cargo" 2>/dev/null || true
    fi
fi

echo "DevDesk Base installation complete!"
