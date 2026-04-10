#!/usr/bin/env bash
# setup.sh — standalone installer for portal
# Run this inside an already-running devcontainer (requires sudo).
#
# Usage:
#   sudo bash setup.sh [--services "name:port:desc:icon,..."] [--links "name:port:desc:icon,..."] [--no-ttyd] [--ttyd-port 7681] [--user vscode]
#
set -e

# ---------- defaults ----------
SERVICES="noVNC:6080:VNC web client:monitor,Code Server:8888:VS Code in browser:code:true"
LINKS=""
TTYD="true"
TTYD_PORT="7681"
EXPLICIT_USER=""

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --services)   SERVICES="$2";      shift 2 ;;
        --links)      LINKS="$2";         shift 2 ;;
        --no-ttyd)    TTYD="false";       shift ;;
        --ttyd-port)  TTYD_PORT="$2";     shift 2 ;;
        --user)       EXPLICIT_USER="$2"; shift 2 ;;
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

echo "==> portal setup"
echo "    user:      $_REMOTE_USER ($_REMOTE_USER_HOME)"
echo "    services:  $SERVICES"
echo "    links:     ${LINKS:-none}"
echo "    ttyd:      $TTYD (port $TTYD_PORT)"
echo ""

# ---------- delegate to install.sh ----------
export _REMOTE_USER _REMOTE_USER_HOME SERVICES LINKS TTYD TTYD_PORT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/install.sh"

# ---------- reload / restart supervisor services ----------
if pgrep -x supervisord > /dev/null; then
    echo "==> Reloading supervisor services..."
    supervisorctl reread
    supervisorctl update
    supervisorctl restart nginx 2>/dev/null || supervisorctl start nginx
    if [[ "$TTYD" == "true" ]]; then
        supervisorctl restart ttyd 2>/dev/null || supervisorctl start ttyd
    fi
else
    echo "==> Starting supervisord..."
    supervisord -c /etc/supervisor/supervisord.conf
fi

echo "==> Done! Portal is available at http://localhost:80"
