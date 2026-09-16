#!/bin/bash

set -e

NOVNC_DIR=$(echo /usr/local/novnc/noVNC-*)

if [ ! -d "$NOVNC_DIR" ]; then
    echo "ERROR: noVNC not found"
    exit 1
fi

echo "noVNC found: $NOVNC_DIR"

if [ ! -f "$NOVNC_DIR/app/clipboard-sync.js" ]; then
    echo "ERROR: clipboard-sync.js not installed"
    exit 1
fi

echo "clipboard-sync.js installed"

# The script is served as a module, so a moved noVNC internal breaks it in the
# browser with nothing to see in the install log.
for module in app/ui.js core/input/keysym.js core/input/util.js core/util/browser.js; do
    if [ ! -f "$NOVNC_DIR/$module" ]; then
        echo "ERROR: clipboard-sync.js imports $module, which is missing"
        exit 1
    fi
done

echo "noVNC modules imported by clipboard-sync.js found"

# index.html is a copy of vnc.html, so both entry points must carry the script.
for page in vnc.html index.html; do
    if ! grep -q 'src="app/clipboard-sync.js"' "$NOVNC_DIR/$page"; then
        echo "ERROR: $page does not load clipboard-sync.js"
        exit 1
    fi
done

echo "vnc.html and index.html load clipboard-sync.js"

INIT_SCRIPT=/usr/local/share/desktop-init.sh

if [ ! -f "$INIT_SCRIPT" ]; then
    echo "ERROR: desktop-init.sh not found"
    exit 1
fi

for option in "-SendPrimary no" "-SetPrimary no" "-UseBlacklist no"; do
    if ! grep -q -- "$option" "$INIT_SCRIPT"; then
        echo "ERROR: desktop-init.sh does not pass $option to TigerVNC"
        exit 1
    fi
done

echo "desktop-init.sh passes the clipboard and blacklist options"

# The default password option must reach TigerVNC. Deciding this at runtime
# once left every desktop unauthenticated.
if ! grep -q -- "-passwd /usr/local/etc/vscode-dev-containers/vnc-passwd" "$INIT_SCRIPT"; then
    echo "ERROR: desktop-init.sh does not use the VNC password file"
    exit 1
fi

if grep -q -- "-SecurityTypes None" "$INIT_SCRIPT"; then
    echo "ERROR: desktop-init.sh still falls back to SecurityTypes None"
    exit 1
fi

if [ ! -s /usr/local/etc/vscode-dev-containers/vnc-passwd ]; then
    echo "ERROR: VNC password file is missing or empty"
    exit 1
fi

echo "desktop-init.sh authenticates with the VNC password file"

echo "All desktop-dark tests passed!"
