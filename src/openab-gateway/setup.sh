#!/usr/bin/env bash
# setup.sh — standalone installer for openab-gateway
# Run this inside an already-running devcontainer (requires sudo).
#
# Usage:
#   sudo bash setup.sh [--version <git-ref>] [--repo-url <url>]
#                      [--listen-addr <host:port>] [--autostart]
#                      [--user <username>]
#
set -e

# ---------- defaults (match devcontainer-feature.json) ----------
VERSION="latest"
REPOURL="https://github.com/openabdev/openab.git"
LISTENADDR="0.0.0.0:8080"
AUTOSTART="false"
EXPLICIT_USER=""

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)     VERSION="$2";        shift 2 ;;
        --repo-url)    REPOURL="$2";        shift 2 ;;
        --listen-addr) LISTENADDR="$2";     shift 2 ;;
        --autostart)   AUTOSTART="true";    shift ;;
        --user)        EXPLICIT_USER="$2";  shift 2 ;;
        -h|--help)
            sed -n '2,9p' "$0"
            exit 0
            ;;
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

echo "==> openab-gateway setup"
echo "    user:           $_REMOTE_USER ($_REMOTE_USER_HOME)"
echo "    openab ref:     $VERSION"
echo "    repo:           $REPOURL"
echo "    listen addr:    $LISTENADDR"
echo "    autostart:      $AUTOSTART"
echo ""

# ---------- delegate to install.sh ----------
export _REMOTE_USER _REMOTE_USER_HOME
export VERSION REPOURL LISTENADDR AUTOSTART

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/install.sh"

# ---------- reload / restart supervisor services ----------
if pgrep -x supervisord > /dev/null; then
    echo "==> Reloading supervisor services..."
    supervisorctl reread
    supervisorctl update
    if [[ "$AUTOSTART" == "true" ]]; then
        # Mirror entrypoint logic — only start if a platform credential is set.
        if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] \
            || [[ -n "${FEISHU_APP_ID:-}" ]] \
            || [[ -n "${LINE_CHANNEL_SECRET:-}" ]] \
            || [[ "${GOOGLE_CHAT_ENABLED:-}" == "true" || "${GOOGLE_CHAT_ENABLED:-}" == "1" ]]; then
            supervisorctl restart openab-gateway 2>/dev/null || supervisorctl start openab-gateway
        else
            echo "    WARNING: autostart=true but no platform credentials are set — gateway not started."
        fi
    fi
else
    echo "==> supervisord not running — start it via your container entrypoint, then:"
    echo "    sudo supervisorctl start openab-gateway"
fi

echo "==> Done! gateway binary: /usr/local/bin/openab-gateway    listen: $LISTENADDR"
