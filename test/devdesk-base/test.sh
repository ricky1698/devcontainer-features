#!/bin/bash

set -e

# Test that mise is installed
if ! command -v mise &> /dev/null; then
    echo "ERROR: mise not found"
    exit 1
fi

echo "mise found: $(mise --version)"

# Test that supervisor is installed
if ! command -v supervisord &> /dev/null; then
    echo "ERROR: supervisor not found"
    exit 1
fi

echo "supervisor found: $(supervisord --version)"

echo "All devdesk-base tests passed!"
