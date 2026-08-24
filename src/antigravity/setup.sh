#!/usr/bin/env bash
# setup.sh — standalone installer for antigravity (agy remote-control daemon)
# Run this inside an already-running devcontainer (requires sudo).
#
# Usage:
#   sudo bash setup.sh [--instance-name <name>] [--no-auto-update]
#                      [--autostart] [--user <username>]
#
set -e

# ---------- defaults (match devcontainer-feature.json) ----------
INSTANCENAME=""
AUTOUPDATE="true"
AUTOSTART="false"
EXPLICIT_USER=""

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --instance-name)  INSTANCENAME="$2"; shift 2 ;;
        --no-auto-update) AUTOUPDATE="false"; shift ;;
        --autostart)      AUTOSTART="true";  shift ;;
        --user)           EXPLICIT_USER="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,8p' "$0"
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

echo "==> antigravity setup"
echo "    user:          $_REMOTE_USER ($_REMOTE_USER_HOME)"
echo "    instance name: ${INSTANCENAME:-<saved or generated>}"
echo "    auto-update:   $AUTOUPDATE"
echo "    autostart:     $AUTOSTART"
echo ""

# ---------- delegate to install.sh ----------
export _REMOTE_USER _REMOTE_USER_HOME
export INSTANCENAME AUTOUPDATE AUTOSTART

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/install.sh"

# ---------- warn about a leftover systemd/launchd daemon ----------
# Two managers restarting the same CLI fight over the hub port and the auth
# token, so retire the old one by hand before relying on supervisor.
SYSTEMD_UNIT="$_REMOTE_USER_HOME/.config/systemd/user/agy-remote-control.service"
if [[ -f "$SYSTEMD_UNIT" ]]; then
    echo ""
    echo "==> NOTE: the systemd user unit is still installed:"
    echo "    $SYSTEMD_UNIT"
    echo "    Retire it so it doesn't race supervisor for the same daemon:"
    echo "      systemctl --user disable --now agy-remote-control.service"
    echo "      systemctl --user disable --now agy-remote-control-update.timer"
fi

# ---------- reload / restart supervisor services ----------
if pgrep -x supervisord > /dev/null; then
    echo "==> Reloading supervisor services..."
    supervisorctl reread
    supervisorctl update
    if [[ "$AUTOSTART" == "true" ]]; then
        if [[ ! -s "$_REMOTE_USER_HOME/.gemini/jetski-standalone-oauth-token" ]]; then
            echo "    WARNING: autostart=true but no auth token — the daemon will exit until you run 'agy-remote-control-login'."
        fi
        supervisorctl restart antigravity 2>/dev/null || supervisorctl start antigravity
    fi
else
    echo "==> supervisord not running — start it via your container entrypoint, then:"
    echo "    sudo supervisorctl start antigravity"
fi

echo "==> Done! Sign in once with: agy-remote-control-login"
