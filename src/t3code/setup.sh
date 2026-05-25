#!/usr/bin/env bash
# setup.sh — standalone installer for t3code
# Run this inside an already-running devcontainer (requires sudo).
#
# Usage:
#   sudo bash setup.sh [--hostname 0.0.0.0] [--no-autostart] [--user vscode]
#
set -e

# ---------- defaults ----------
T3_HOSTNAME="0.0.0.0"
AUTOSTART="true"
EXPLICIT_USER=""

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)     T3_HOSTNAME="$2";   shift 2 ;;
        --no-autostart) AUTOSTART="false";  shift ;;
        --user)         EXPLICIT_USER="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------- resolve target user ----------
if [[ -n "$EXPLICIT_USER" ]]; then
    _REMOTE_USER="$EXPLICIT_USER"
elif [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" ]]; then
    _REMOTE_USER="$SUDO_USER"
elif [[ "$(whoami)" != "root" ]]; then
    _REMOTE_USER="$(whoami)"
else
    for candidate in vscode codespace ubuntu debian user; do
        if id "$candidate" &>/dev/null; then
            _REMOTE_USER="$candidate"
            break
        fi
    done
    if [[ -z "$_REMOTE_USER" ]]; then
        echo "ERROR: Could not detect a non-root user. Pass --user <username> explicitly."
        exit 1
    fi
fi

_REMOTE_USER_HOME=$(getent passwd "$_REMOTE_USER" | cut -d: -f6)

echo "==> t3code setup"
echo "    user:      $_REMOTE_USER ($_REMOTE_USER_HOME)"
echo "    hostname:  $T3_HOSTNAME"
echo "    autostart: $AUTOSTART"
echo ""

# ---------- delegate to install.sh ----------
# Note: install.sh reads $HOSTNAME, which collides with the shell's built-in
# HOSTNAME variable. Export explicitly so the script sees our value.
export _REMOTE_USER _REMOTE_USER_HOME AUTOSTART
export HOSTNAME="$T3_HOSTNAME"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/install.sh"

# ---------- reload / restart supervisor services ----------
if pgrep -x supervisord > /dev/null; then
    echo "==> Reloading supervisor services..."
    supervisorctl reread
    supervisorctl update
    if [[ "$AUTOSTART" == "true" ]]; then
        supervisorctl restart t3code 2>/dev/null || supervisorctl start t3code
        supervisorctl restart t3-pair-server 2>/dev/null || supervisorctl start t3-pair-server
        supervisorctl restart t3-tmp-cleaner 2>/dev/null || supervisorctl start t3-tmp-cleaner
    fi
    # Reload nginx so the new /api/t3-pair location takes effect (if portal is installed).
    if [ -f /etc/nginx/sites-available/portal ]; then
        supervisorctl restart nginx 2>/dev/null || true
    fi
else
    echo "==> Starting supervisord..."
    supervisord -c /etc/supervisor/supervisord.conf
fi

echo "==> Done! T3Code is available at http://localhost:3773"
