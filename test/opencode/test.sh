#!/bin/bash

set -e

# Test that opencode config exists
if [ ! -f /etc/supervisor/conf.d/opencode.conf ]; then
    echo "ERROR: OpenCode supervisor config not found"
    exit 1
fi

echo "OpenCode supervisor config found"

echo "All opencode tests passed!"
