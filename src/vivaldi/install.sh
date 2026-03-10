#!/usr/bin/env bash
set -e

echo "Installing Vivaldi..."

curl -fsSL https://repo.vivaldi.com/archive/linux_signing_key.pub \
    | gpg --yes --dearmor -o /usr/share/keyrings/vivaldi.gpg

cat > /etc/apt/sources.list.d/vivaldi.sources << 'EOF'
Types: deb
URIs: https://repo.vivaldi.com/stable/deb/
Suites: stable
Components: main
Architectures: amd64 arm64 armhf
Signed-By: /usr/share/keyrings/vivaldi.gpg
EOF

apt-get update
apt-get install -y vivaldi-stable
rm -rf /var/lib/apt/lists/*

echo "Vivaldi installation complete!"
