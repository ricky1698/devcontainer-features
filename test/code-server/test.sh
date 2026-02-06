#!/bin/bash

set -e

# Test that code-server supervisor config exists
if [ ! -f /etc/supervisor/conf.d/code-server.conf ]; then
    echo "ERROR: code-server supervisor config not found"
    exit 1
fi

echo "code-server supervisor config found"

echo "All code-server tests passed!"
