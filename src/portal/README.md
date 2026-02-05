
# Portal (portal)

DevDesk Portal with nginx reverse proxy for web services on port 80

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/portal:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| services | Comma-separated services in format name:port:description:icon | string | noVNC:6080:VNC web client:monitor,Code Server:8888:VS Code in browser:terminal |

## How it works

The portal configures nginx as a reverse proxy on port 80. Each service defined in the `services` option will be accessible through a path-based URL:
- Service names are converted to URL-safe paths (lowercase, spaces replaced with hyphens)
- Example: "Code Server" becomes accessible at `/code-server/`
- The portal UI is accessible at the root path `/`


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/portal/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
