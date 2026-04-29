#!/usr/bin/env bash
set -e

echo "Installing Google Chrome..."

architecture="$(dpkg --print-architecture)"
if [ "${architecture}" != "amd64" ]; then
    echo "ERROR: Google Chrome for Linux is only available for amd64. Detected: ${architecture}"
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
    | gpg --yes --dearmor -o /etc/apt/keyrings/google-chrome.gpg
chmod a+r /etc/apt/keyrings/google-chrome.gpg

cat > /etc/apt/sources.list.d/google-chrome.sources << 'EOF'
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/google-chrome.gpg
EOF

apt-get update
apt-get install -y google-chrome-stable
rm -rf /var/lib/apt/lists/*

echo "Google Chrome installation complete!"
