# DevContainer Features

A collection of dev container features for DevDesk development environments.

## Features

| Feature | Description |
|---------|-------------|
| [devdesk-base](./src/devdesk-base) | Base environment with mise, CLI tools, and supervisor |
| [portal](./src/portal) | DevDesk Portal with nginx for service discovery |
| [tailscale-setup](./src/tailscale-setup) | Automatic Tailscale setup with OAuth token |
| [vibetunnel](./src/vibetunnel) | VibeTunnel MCP tunnel service |
| [opencode](./src/opencode) | OpenCode AI-powered code editor |

## Usage

Add features to your `devcontainer.json`:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
    "features": {
        "ghcr.io/ricky1698/devcontainer-features/devdesk-base:1": {
            "packages": "node@lts,bun@1,gh@latest"
        },
        "ghcr.io/ricky1698/devcontainer-features/portal:1": {
            "port": "8080"
        },
        "ghcr.io/ricky1698/devcontainer-features/tailscale-setup:1": {},
        "ghcr.io/ricky1698/devcontainer-features/vibetunnel:1": {},
        "ghcr.io/ricky1698/devcontainer-features/opencode:1": {}
    }
}
```

## Feature Details

### devdesk-base

Installs:
- mise (runtime manager)
- supervisor (process manager)
- Common CLI tools via mise (configurable)
- npm global packages (configurable)

Options:
- `installMise`: Install mise (default: true)
- `installSupervisor`: Install supervisor (default: true)
- `packages`: Comma-separated mise packages (default: common dev tools)
- `npmGlobalPackages`: Comma-separated npm packages

### portal

A web portal for discovering and accessing DevDesk services.

Options:
- `port`: Portal port (default: 8080)
- `enableVnc`: Include VNC link (default: true)
- `enableCodeServer`: Include code-server link (default: true)
- `codeServerPort`: Code-server port for links (default: 8888)

### tailscale-setup

Automatic Tailscale configuration using `TS_OAUTH_TOKEN` environment variable.

Options:
- `autoConnect`: Auto-connect on start (default: true)
- `enableSsh`: Enable Tailscale SSH (default: true)
- `acceptRoutes`: Accept Tailscale routes (default: true)

### vibetunnel

VibeTunnel MCP tunnel service with supervisor management.

Options:
- `noAuth`: Run without authentication (default: true)
- `autostart`: Auto-start via supervisor (default: true)

### opencode

OpenCode AI editor with supervisor management.

Options:
- `hostname`: Bind hostname (default: 0.0.0.0)
- `autostart`: Auto-start via supervisor (default: true)

## Development

1. Clone this repository
2. Make changes to features in `src/`
3. Push to `main` to publish

Features are automatically published to GHCR on push to main.

## License

MIT
