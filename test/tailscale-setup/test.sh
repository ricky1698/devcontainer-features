#!/bin/bash

set -e

# Test that tailscale-setup script exists
if [ ! -f /usr/local/bin/tailscale-setup ]; then
    echo "ERROR: Tailscale setup script not found"
    exit 1
fi

echo "Tailscale setup script found"

echo "All tailscale-setup tests passed!"
