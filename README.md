# DevContainer Features

A collection of dev container features for DevDesk development environments.

## Features

| Feature | Description |
|---------|-------------|
| [devdesk-base](./src/devdesk-base) | Base environment with mise, CLI tools, and supervisor |
| [portal](./src/portal) | DevDesk Portal with nginx for service discovery |
| [vibetunnel](./src/vibetunnel) | VibeTunnel MCP tunnel service |
| [opencode](./src/opencode) | OpenCode AI-powered code editor |
| [chrome](./src/chrome) | Google Chrome stable via official apt repository |

## Usage

Add features to your `devcontainer.json`:

```jsonc
{
    "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
    "features": {
        "ghcr.io/ricky1698/devcontainer-features/devdesk-base:1": {
            "packages": "node@lts,bun@1,gh@latest"
        },
        "ghcr.io/ricky1698/devcontainer-features/portal:1": {},
        "ghcr.io/ricky1698/devcontainer-features/vibetunnel:1": {},
        "ghcr.io/ricky1698/devcontainer-features/opencode:1": {},
        "ghcr.io/ricky1698/devcontainer-features/chrome:1": {}
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

A web portal with nginx reverse proxy for discovering and accessing DevDesk services on port 80.

Options:
- `services`: Comma-separated services in format name:port:description:icon

The portal acts as a reverse proxy, making services accessible through path-based URLs (e.g., `/code-server/`, `/novnc/`).

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

### chrome

Installs Google Chrome stable from Google's official apt repository.

Options: none

## Development

1. Clone this repository
2. Make changes to features in `src/`
3. Push to `main` to publish

Features are automatically published to GHCR on push to main.

## License

MIT
