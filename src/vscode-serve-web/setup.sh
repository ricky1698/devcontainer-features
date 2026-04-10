#!/usr/bin/env bash
# setup.sh — standalone installer for vscode-serve-web
# Run this inside an already-running devcontainer (requires sudo).
#
# Usage:
#   sudo bash setup.sh [--port 8888] [--host 0.0.0.0] [--with-token] [--base-path /code-server] [--user vscode] [--extensions "ms-python.python,eamodio.gitlens"]
#
set -e

# ---------- defaults ----------
PORT=8888
HOST=0.0.0.0
CONNECTIONTOKEN=false
SERVERBASEPATH="/code-server"
EXTENSIONS=""
EXPLICIT_USER=""

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)        PORT="$2";           shift 2 ;;
        --host)        HOST="$2";           shift 2 ;;
        --with-token)  CONNECTIONTOKEN=true; shift ;;
        --base-path)   SERVERBASEPATH="$2"; shift 2 ;;
        --extensions)  EXTENSIONS="$2";     shift 2 ;;
        --user)        EXPLICIT_USER="$2";  shift 2 ;;
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

echo "==> vscode-serve-web setup"
echo "    user:       $_REMOTE_USER ($_REMOTE_USER_HOME)"
echo "    listen:     $HOST:$PORT"
echo "    base path:  $SERVERBASEPATH"
echo "    token:      $CONNECTIONTOKEN"
echo "    extensions: ${EXTENSIONS:-none}"
echo ""

# ---------- delegate to install.sh ----------
export _REMOTE_USER _REMOTE_USER_HOME PORT HOST CONNECTIONTOKEN SERVERBASEPATH EXTENSIONS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/install.sh"
