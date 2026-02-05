#!/bin/bash

set -e

# Test that vibetunnel config exists
if [ ! -f /etc/supervisor/conf.d/vibetunnel.conf ]; then
    echo "ERROR: VibeTunnel supervisor config not found"
    exit 1
fi

echo "VibeTunnel supervisor config found"

echo "All vibetunnel tests passed!"
