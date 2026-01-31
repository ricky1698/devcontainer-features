
# Portal (portal)

DevDesk Portal with nginx reverse proxy for web services

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/portal:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| port | Port for the portal nginx server | string | 8080 |
| services | Comma-separated services in format name:port:description:icon | string | noVNC:6080:VNC web client:monitor,Code Server:8888:VS Code in browser:terminal |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/portal/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
