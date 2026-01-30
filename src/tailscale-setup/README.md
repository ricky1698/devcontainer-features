
# Tailscale Auto-Setup (tailscale-setup)

Automatic Tailscale setup with OAuth token from environment

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/tailscale-setup:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| autoConnect | Automatically connect to Tailscale on container start if TS_OAUTH_TOKEN is set | boolean | true |
| enableSsh | Enable Tailscale SSH | boolean | true |
| acceptRoutes | Accept routes from Tailscale | boolean | true |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/tailscale-setup/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
