
# Desktop (Dark Theme) (desktop-dark)

Lightweight Fluxbox desktop with dark theme, accessible via VNC viewer or web browser. Based on devcontainers/features/desktop-lite with built-in dark mode support.

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/desktop-dark:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| noVncVersion | The noVNC version to use | string | 1.6.0 |
| password | Desktop connection password. Use "noPassword" for localhost-only access without authentication | string | vscode |
| webPort | Port for the VNC web client (noVNC) | string | 6080 |
| vncPort | Port for the desktop VNC server (TigerVNC) | string | 5901 |
| backgroundColor | Desktop background color (hex) | string | #1E1E1E |
| gtkTheme | GTK theme name for applications | string | Adwaita-dark |
| gtkIconTheme | GTK icon theme name | string | Adwaita |

## Clipboard

The noVNC page loads `clipboard-sync.js`, which syncs the clipboard when you
press a shortcut inside the desktop instead of through the noVNC clipboard
panel:

- Ctrl+V (Cmd+V on macOS) sends the local clipboard text to the desktop, then
  delivers the keystroke, so the focused application pastes the new text.
- Ctrl+C or Ctrl+X (Cmd+C or Cmd+X on macOS) delivers the keystroke and writes
  the next text the desktop copies, within two seconds, to the local
  clipboard. Terminal shortcuts with Shift work the same way.

Browsers allow clipboard access only on HTTPS or localhost pages and only
during a user gesture, which is why both directions start from the shortcut.
VS Code port forwarding and Codespaces both qualify. Reaching the web port
over plain HTTP does not: pasting still works, but copying out of the desktop
fails silently. Copying from an application menu or right-click menu updates
only the noVNC clipboard panel.

TigerVNC runs with `SendPrimary` and `SetPrimary` off, so only the CLIPBOARD
selection is shared. Selecting text in the desktop does not change the local
clipboard, and a paste replaces the selected text instead of clearing it.

`clipboard-sync.js` imports noVNC internals, so it is tied to the noVNC
version. Changing `noVncVersion` away from the default may break clipboard
sync, and the install fails outright if the script can no longer be injected
into the noVNC page.

## Password

The `password` option now takes effect. Before version 1.1.0 the generated
entrypoint decided its security type from a `VNC_PASSWORD` variable that
nothing ever set, so every desktop ran with `SecurityTypes None` regardless of
the option. Upgrading an environment that relied on that will start asking for
the password, `vscode` unless you changed it. Set `password` to `noPassword`
to keep an unauthenticated desktop.

The web port is served on all interfaces. With `noPassword`, anyone who can
route to it gets a session, and every Ctrl+V you press pushes your local
clipboard into it. Only use `noPassword` where access is already restricted.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/desktop-dark/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
