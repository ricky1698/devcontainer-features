#!/usr/bin/env bash
# setup.sh — standalone installer for openab-broker
# Run this inside an already-running devcontainer (requires sudo).
#
# Usage:
#   sudo bash setup.sh [--version <git-ref>] [--repo-url <url>]
#                      [--default-agent <kiro-cli|claude|codex|gemini|copilot>]
#                      [--config-path <path>] [--allowed-channels <ids>]
#                      [--max-sessions <n>] [--autostart] [--user <username>]
#
set -e

# ---------- defaults (match devcontainer-feature.json) ----------
VERSION="main"
REPOURL="https://github.com/openabdev/openab.git"
DEFAULTAGENT="copilot"
CONFIGPATH="/etc/openab/config.toml"
ALLOWEDCHANNELS=""
MAXSESSIONS="10"
AUTOSTART="false"
EXPLICIT_USER=""

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)          VERSION="$2";          shift 2 ;;
        --repo-url)         REPOURL="$2";          shift 2 ;;
        --default-agent)    DEFAULTAGENT="$2";     shift 2 ;;
        --config-path)      CONFIGPATH="$2";       shift 2 ;;
        --allowed-channels) ALLOWEDCHANNELS="$2";  shift 2 ;;
        --max-sessions)     MAXSESSIONS="$2";      shift 2 ;;
        --autostart)        AUTOSTART="true";      shift ;;
        --user)             EXPLICIT_USER="$2";    shift 2 ;;
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

echo "==> openab-broker setup"
echo "    user:             $_REMOTE_USER ($_REMOTE_USER_HOME)"
echo "    openab ref:       $VERSION"
echo "    repo:             $REPOURL"
echo "    default agent:    $DEFAULTAGENT"
echo "    config path:      $CONFIGPATH"
echo "    allowed channels: ${ALLOWEDCHANNELS:-<placeholder>}"
echo "    max sessions:     $MAXSESSIONS"
echo "    autostart:        $AUTOSTART"
echo ""

# ---------- delegate to install.sh ----------
export _REMOTE_USER _REMOTE_USER_HOME
export VERSION REPOURL DEFAULTAGENT CONFIGPATH ALLOWEDCHANNELS MAXSESSIONS AUTOSTART

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/install.sh"

# ---------- reload / restart supervisor services ----------
if pgrep -x supervisord > /dev/null; then
    echo "==> Reloading supervisor services..."
    supervisorctl reread
    supervisorctl update
    if [[ "$AUTOSTART" == "true" ]]; then
        if [[ -z "${DISCORD_BOT_TOKEN:-}" ]]; then
            echo "    WARNING: autostart=true but DISCORD_BOT_TOKEN is not set — broker will fail to start."
        fi
        supervisorctl restart openab 2>/dev/null || supervisorctl start openab
    fi
else
    echo "==> supervisord not running — start it via your container entrypoint, then:"
    echo "    sudo supervisorctl start openab"
fi

echo "==> Done! openab binary: /usr/local/bin/openab    config: $CONFIGPATH"
