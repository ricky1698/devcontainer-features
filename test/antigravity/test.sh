#!/bin/bash
set -e

fail() { echo "ERROR: $1"; exit 1; }

AGY_BIN="$HOME/.local/bin/agy"
[[ -x "$AGY_BIN" ]] || fail "agy binary not found at $AGY_BIN"
"$AGY_BIN" --help >/dev/null 2>&1 || fail "agy --help failed"

[[ -x /usr/local/bin/agy-remote-control ]] || fail "launcher wrapper missing or not executable"
bash -n /usr/local/bin/agy-remote-control || fail "launcher wrapper has a syntax error"
grep -q '^exec 0</dev/null$' /usr/local/bin/agy-remote-control || fail "launcher wrapper does not redirect stdin from /dev/null"

[[ -x /usr/local/bin/agy-remote-control-login ]] || fail "login helper missing or not executable"
bash -n /usr/local/bin/agy-remote-control-login || fail "login helper has a syntax error"

[[ -f /etc/supervisor/conf.d/antigravity.conf ]] || fail "supervisor config not found"
grep -q '^\[program:antigravity\]' /etc/supervisor/conf.d/antigravity.conf || fail "supervisor config missing [program:antigravity]"
grep -q '^command=/usr/local/bin/agy-remote-control$' /etc/supervisor/conf.d/antigravity.conf || fail "supervisor config does not run the wrapper"
grep -q 'AGY_CLI_DISABLE_AUTO_UPDATE="false"' /etc/supervisor/conf.d/antigravity.conf || fail "supervisor config missing AGY_CLI_DISABLE_AUTO_UPDATE=false"

[[ -x /usr/local/bin/devdesk-antigravity-entrypoint ]] || fail "entrypoint script missing or not executable"

echo "All antigravity tests passed!"
