// Sync the local and remote clipboards when the user presses the copy or
// paste shortcut inside the desktop. Browsers only grant clipboard access
// during a user gesture, so both directions start from that keydown.
//
// This file imports noVNC internals, so it is tied to the noVNC version the
// feature installs. Re-check it when changing the noVncVersion option.

import UI from "./ui.js";
import KeyTable from "../core/input/keysym.js";
import { getKeysym } from "../core/input/util.js";
import { isMac } from "../core/util/browser.js";

// A remote copy normally arrives within tens of milliseconds. Ctrl+C in a
// terminal never produces one, so give up rather than hold the write open.
const COPY_TIMEOUT_MS = 2000;
// Browsers dispatch the paste event right after keydown. If it never comes,
// still deliver the keystroke so the remote app pastes its own clipboard.
const PASTE_FALLBACK_MS = 100;

let pendingPaste = null;
let pendingCopy = null;

function shortcutAction(event) {
    const modifier = isMac() ? event.metaKey : event.ctrlKey;
    if (!modifier || event.altKey) {
        return null;
    }
    switch (event.key.toLowerCase()) {
        case "v":
            return "paste";
        case "c":
        case "x":
            return "copy";
        default:
            return null;
    }
}

function activeDesktop(event) {
    const rfb = UI.rfb;
    if (!UI.connected || !rfb || rfb.viewOnly) {
        return null;
    }
    if (!document.getElementById("noVNC_container").contains(event.target)) {
        return null;
    }
    return rfb;
}

// Send the shortcut as Ctrl+key. noVNC forwards Cmd as Alt or Super on macOS,
// so release those and press Ctrl instead.
function sendShortcut(rfb, event) {
    // On Windows noVNC holds back Ctrl for up to 100 ms to detect AltGr.
    // Flush it so the remote sees Ctrl before the key.
    rfb._keyboard._interruptAltGrSequence();
    if (isMac()) {
        rfb.sendKey(KeyTable.XK_Alt_L, "MetaLeft", false);
        rfb.sendKey(KeyTable.XK_Super_L, "MetaRight", false);
        rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", true);
    }
    rfb.sendKey(getKeysym(event), event.code);
    if (isMac()) {
        rfb.sendKey(KeyTable.XK_Control_L, "ControlLeft", false);
    }
}

// text is the local clipboard text, or null when the browser gave us none.
// An empty string is a real value: it clears the desktop clipboard, so an
// empty local clipboard pastes nothing instead of stale remote text.
function finishPaste(text) {
    if (pendingPaste === null) {
        return;
    }
    const { rfb, event, timer } = pendingPaste;
    pendingPaste = null;
    clearTimeout(timer);
    if (text !== null) {
        rfb.clipboardPasteFrom(text);
    }
    sendShortcut(rfb, event);
}

function startCopy(rfb, event) {
    sendShortcut(rfb, event);
    if (!window.ClipboardItem || !navigator.clipboard?.write) {
        return;
    }
    pendingCopy?.reject(new Error("superseded by a newer copy"));
    const text = new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
            pendingCopy = null;
            reject(new Error("remote clipboard did not change"));
        }, COPY_TIMEOUT_MS);
        pendingCopy = {
            resolve(value) {
                clearTimeout(timer);
                resolve(new Blob([value], { type: "text/plain" }));
            },
            reject(error) {
                clearTimeout(timer);
                reject(error);
            },
        };
    });
    // Safari requires write() to be called inside the gesture, so pass the
    // pending remote text as a promise.
    navigator.clipboard
        .write([new ClipboardItem({ "text/plain": text })])
        .catch(() => {});
}

window.addEventListener(
    "keydown",
    (event) => {
        const action = shortcutAction(event);
        const rfb = action && activeDesktop(event);
        if (!rfb) {
            return;
        }
        // Keep noVNC from forwarding the key now. Do not preventDefault, or
        // the browser will not fire the paste event.
        event.stopImmediatePropagation();
        if (action === "paste") {
            finishPaste(null);
            pendingPaste = {
                rfb,
                event,
                timer: setTimeout(() => finishPaste(null), PASTE_FALLBACK_MS),
            };
        } else {
            event.preventDefault();
            startCopy(rfb, event);
        }
    },
    true
);

// Releasing the modifier before the paste event would make the fallback send
// a bare "v", so deliver the shortcut before noVNC forwards the release.
window.addEventListener(
    "keyup",
    (event) => {
        if (pendingPaste !== null && event.key === (isMac() ? "Meta" : "Control")) {
            finishPaste(null);
        }
    },
    true
);

document.addEventListener("paste", (event) => {
    if (pendingPaste === null) {
        return;
    }
    event.preventDefault();
    // Chromium reports no types at all for an empty clipboard, so read the
    // text rather than looking for text/plain among the types.
    finishPaste(event.clipboardData?.getData("text/plain") ?? null);
});

// noVNC adds UI.clipboardReceive to every new RFB connection.
const clipboardReceive = UI.clipboardReceive;
UI.clipboardReceive = (event) => {
    clipboardReceive(event);
    if (pendingCopy !== null) {
        const copy = pendingCopy;
        pendingCopy = null;
        copy.resolve(event.detail.text);
    }
};
