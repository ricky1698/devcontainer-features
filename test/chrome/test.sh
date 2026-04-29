#!/bin/bash

set -e

if ! command -v google-chrome &> /dev/null; then
    echo "ERROR: google-chrome not found"
    exit 1
fi

echo "google-chrome found: $(google-chrome --version)"

if [ ! -f /etc/apt/sources.list.d/google-chrome.sources ]; then
    echo "ERROR: Google Chrome apt source not found"
    exit 1
fi

echo "Google Chrome apt source found"

echo "All chrome tests passed!"
