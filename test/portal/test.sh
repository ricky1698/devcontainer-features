#!/bin/bash

set -e

# Optional: Import test library
# source dev-container-features-test-lib

# Test that nginx is installed
if ! command -v nginx &> /dev/null; then
    echo "ERROR: nginx not found"
    exit 1
fi

echo "nginx found: $(nginx -v 2>&1)"

# Test that the portal nginx config exists
if [ ! -f /etc/nginx/sites-available/portal ]; then
    echo "ERROR: Portal nginx config not found"
    exit 1
fi

echo "Portal nginx config found"

# Test that supervisord is configured
if [ ! -f /etc/supervisor/conf.d/nginx.conf ]; then
    echo "ERROR: Supervisor nginx config not found"
    exit 1
fi

echo "Supervisor nginx config found"

# Test that portal files exist
if [ ! -f /var/www/portal/index.html ]; then
    echo "ERROR: Portal index.html not found"
    exit 1
fi

echo "Portal HTML found"

if [ ! -f /var/www/portal/services.yaml ]; then
    echo "ERROR: Portal services.yaml not found"
    exit 1
fi

echo "Portal services.yaml found"

# Test that links.yaml exists (can be empty)
if [ ! -f /var/www/portal/links.yaml ]; then
    echo "ERROR: Portal links.yaml not found"
    exit 1
fi

echo "Portal links.yaml found"

# Test that the entrypoint exists
if [ ! -f /usr/local/bin/devdesk-portal-entrypoint ]; then
    echo "ERROR: Portal entrypoint not found"
    exit 1
fi

echo "Portal entrypoint found"

# Validate nginx config syntax (ignore permission errors on pid file)
# The config syntax is valid even if we can't test the full configuration
if nginx -t 2>&1 | grep -q "syntax is ok"; then
    echo "nginx config syntax is valid"
else
    echo "ERROR: nginx config syntax check failed"
    exit 1
fi

echo "All portal tests passed!"
