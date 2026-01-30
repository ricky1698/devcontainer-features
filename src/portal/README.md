
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
| enableVnc | Include VNC link in portal | boolean | true |
| enableCodeServer | Include code-server link in portal | boolean | true |
| codeServerPort | Port for code-server (for proxy config) | string | 8888 |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/portal/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
