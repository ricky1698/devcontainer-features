#!/bin/bash
set -e

fail() { echo "ERROR: $1"; exit 1; }

[[ -x /usr/local/bin/openab-gateway ]] || fail "openab-gateway binary not found at /usr/local/bin/openab-gateway"
# openab-gateway has no --help/--version flag — invoking it starts the server.
# Skip the run-the-binary smoke check; rely on the file-mode + supervisor config
# assertions below instead.
file /usr/local/bin/openab-gateway 2>/dev/null | grep -q ELF \
    || fail "openab-gateway is not an ELF binary"

[[ -f /etc/supervisor/conf.d/openab-gateway.conf ]] || fail "supervisor config not found"
grep -q '^\[program:openab-gateway\]' /etc/supervisor/conf.d/openab-gateway.conf \
    || fail "supervisor config missing [program:openab-gateway]"
grep -q 'GATEWAY_LISTEN=' /etc/supervisor/conf.d/openab-gateway.conf \
    || fail "supervisor config missing GATEWAY_LISTEN env"

[[ -x /usr/local/bin/devdesk-openab-gateway-entrypoint ]] \
    || fail "entrypoint script missing or not executable"

echo "All openab-gateway tests passed!"
