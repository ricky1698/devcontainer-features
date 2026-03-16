#!/usr/bin/env bash
set -e

echo "Installing Claude Code..."

export HOME="$_REMOTE_USER_HOME"
mkdir -p "$_REMOTE_USER_HOME/.local/bin"

GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases"
DOWNLOAD_DIR="$HOME/.claude/downloads"
mkdir -p "$DOWNLOAD_DIR"

# Detect platform
case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
platform="linux-${arch}"

# Check for musl
if [ -f /lib/libc.musl-x86_64.so.1 ] || [ -f /lib/libc.musl-aarch64.so.1 ] || ldd /bin/ls 2>&1 | grep -q musl; then
    platform="linux-${arch}-musl"
fi

# Get latest version
version=$(curl -fsSL "$GCS_BUCKET/latest")

# Get checksum from manifest
manifest_json=$(curl -fsSL "$GCS_BUCKET/$version/manifest.json")
checksum=$(echo "$manifest_json" | python3 -c "import sys,json; print(json.load(sys.stdin)['platforms']['$platform']['checksum'])")

if [ -z "$checksum" ] || [[ ! "$checksum" =~ ^[a-f0-9]{64}$ ]]; then
    echo "Platform $platform not found in manifest" >&2
    exit 1
fi

# Download binary
binary_path="$DOWNLOAD_DIR/claude-$version-$platform"
curl -fsSL -o "$binary_path" "$GCS_BUCKET/$version/$platform/claude"

# Verify checksum
actual=$(sha256sum "$binary_path" | cut -d' ' -f1)
if [ "$actual" != "$checksum" ]; then
    echo "Checksum verification failed" >&2
    rm -f "$binary_path"
    exit 1
fi

chmod +x "$binary_path"

# Run claude install to set up launcher and shell integration
"$binary_path" install

rm -f "$binary_path"

chown -R "$_REMOTE_USER:$_REMOTE_USER" "$_REMOTE_USER_HOME/.local" "$_REMOTE_USER_HOME/.claude" "$_REMOTE_USER_HOME/.cache" 2>/dev/null || true

echo "Claude Code installation complete!"
echo "  Binary: $_REMOTE_USER_HOME/.local/bin/claude"
