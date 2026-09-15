# Desktop console image

A single-user Fluxbox desktop with Google Chrome, Tilix, Mousepad, TigerVNC,
noVNC, and websockify. Nothing starts automatically except the window manager;
open applications from the right-click menu.

The image contains no cluster names, internal hostnames, or credentials.
Deployment and access controls belong in each infrastructure repository.

## Runtime interface

| Input | Required | Behavior |
|---|---|---|
| `/run/secrets/vnc/password` | Yes | An eight-character visible ASCII VNC password |
| `DESKTOP_GEOMETRY` | No | Initial desktop size as `WIDTHxHEIGHT`, defaults to `1920x1080` |
| `/home/desktop`, `/run/desktop-console`, `/tmp`, `/dev/shm` | Yes | Writable runtime volumes for a read-only root filesystem |

The image exposes TCP 6080. TigerVNC listens only on container loopback TCP
5901 and requires VNC password authentication. Its per-host blacklist is
disabled because websockify makes every browser connection appear to come from
loopback, so one client with a stale password would otherwise lock out every
session. The container runs as UID/GID 10001 with all capabilities dropped and
needs a `/dev/shm` of at least 2 GiB. The container exits when Fluxbox,
TigerVNC, or websockify stops.

Google Chrome's sandbox creates PID and network namespaces and then chroots.
With an unconfined seccomp profile, which is the Kubernetes default, no
capability is needed. Docker's default profile and Kubernetes `RuntimeDefault`
only allow those calls with `CAP_SYS_ADMIN` and `CAP_SYS_CHROOT`, so either add
those two capabilities or use a seccomp profile that permits `clone`,
`unshare`, and `chroot`.

`/home/desktop` receives the Fluxbox menu, style, and GTK dark theme settings
on first start. Mount a persistent volume there to keep browser profiles and
menu edits across restarts. The noVNC client defaults to scaling the desktop
to the browser window; change it from the noVNC settings panel.

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
Copying from an application menu or right-click menu updates only the noVNC
clipboard panel.

TigerVNC runs with `SendPrimary` and `SetPrimary` off, so only the CLIPBOARD
selection is shared. Selecting text in the desktop does not change the local
clipboard, and a paste replaces the selected text instead of clearing it.

The script imports noVNC internals and is tied to the pinned noVNC version.
Run the clipboard test after bumping `NOVNC_VERSION`.

## Local verification

```bash
docker build -t desktop-console:test images/desktop-console
uv run images/desktop-console/smoke-test.py --image desktop-console:test
uv run --with playwright==1.55.0 playwright install --with-deps chromium firefox
uv run images/desktop-console/clipboard-test.py --image desktop-console:test
```

The smoke test covers startup with the default and a custom geometry, noVNC,
WebSocket, six rejected VNC password attempts followed by a successful login,
framebuffer output, Traditional Chinese font
availability, opening Tilix and Google Chrome windows with the sandbox
enabled under both seccomp configurations above, and container exit after
Fluxbox stops. It reuses the VNC client from `images/browser-console`.

The clipboard test drives Chromium and Firefox through noVNC against Mousepad.
It checks that a paste replaces the selection with the new local text, that a
copy reaches the local clipboard, and that a copy with nothing selected leaves
the local clipboard alone.

## Published image

Merges to `main` publish these tags:

- `ghcr.io/ricky1698/devcontainer-features/desktop-console:1.0.0`
- `ghcr.io/ricky1698/devcontainer-features/desktop-console:latest`
- `ghcr.io/ricky1698/devcontainer-features/desktop-console:sha-<commit>`

Pull requests from branches in this repository publish test images after the
smoke and clipboard tests pass:

- `ghcr.io/ricky1698/devcontainer-features/desktop-console:pr-<number>`, which
  moves with each push
- `ghcr.io/ricky1698/devcontainer-features/desktop-console:pr-<number>-<short-sha>`

Bump `VERSION` before changing the image after a release.

GHCR packages are private when first created. After the first publish, set the
`desktop-console` package visibility to public once so clusters can pull it
without an image pull Secret.
