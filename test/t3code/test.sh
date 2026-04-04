#!/bin/bash

set -e

# Test that t3code config exists
if [ ! -f /etc/supervisor/conf.d/t3code.conf ]; then
    echo "ERROR: T3Code supervisor config not found"
    exit 1
fi

echo "T3Code supervisor config found"

echo "All t3code tests passed!"
