## Direct Links Section

The portal now supports a **Direct Links** section for services that don't work well behind a reverse proxy.

### Why use Direct Links?

Some services (like OpenCode) expect to be accessed directly at their port and may not function correctly when accessed through nginx's path-based reverse proxy (e.g., `/opencode/`). For these services, you can use the `links` option to display direct port-based access links in the portal.

### Usage Example

```json
{
  "features": {
    "ghcr.io/ricky1698/devcontainer-features/portal:1": {
      "services": "noVNC:6080:VNC web client:monitor,Code Server:8888:VS Code in browser:terminal",
      "links": "OpenCode:4096:AI-powered code editor:code"
    }
  }
}
```

In this example:
- **Services** (`noVNC`, `Code Server`) will be accessible via reverse proxy at `/novnc/` and `/code-server/`
- **Links** (`OpenCode`) will be shown in a separate "Direct Links" section with a link to `http://hostname:4096`

### Format

Both `services` and `links` use the same format:
```
name:port:description:icon
```

Available icons: `code`, `globe`, `monitor`, `bot`, `terminal`, `default`

Multiple entries are comma-separated.
