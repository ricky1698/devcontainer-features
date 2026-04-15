#!/bin/bash
set -e

fail() { echo "ERROR: $1"; exit 1; }

[[ -x /usr/local/bin/openab ]] || fail "openab binary not found at /usr/local/bin/openab"
/usr/local/bin/openab --help >/dev/null 2>&1 || fail "openab --help failed"

[[ -f /etc/openab/config.toml ]] || fail "config.toml not found at /etc/openab/config.toml"
grep -q '^\[discord\]' /etc/openab/config.toml || fail "config.toml missing [discord] section"
grep -q '^\[agent\]'   /etc/openab/config.toml || fail "config.toml missing [agent] section"

[[ -f /etc/supervisor/conf.d/openab.conf ]] || fail "supervisor config not found"
grep -q '^\[program:openab\]' /etc/supervisor/conf.d/openab.conf || fail "supervisor config missing [program:openab]"

[[ -x /usr/local/bin/devdesk-openab-entrypoint ]] || fail "entrypoint script missing or not executable"

echo "All openab-broker tests passed!"
