# VS Code Serve Web

Official Microsoft VS Code in the browser using `code serve-web` — the built-in web server bundled with the VS Code CLI. Unlike `code-server` (a third-party project), this uses the real Microsoft VS Code, so all first-party extensions (GitHub Copilot, Copilot Chat, etc.) work without workarounds.

## How it works

1. Downloads the official **VS Code CLI** (`code` binary) from Microsoft's update servers.
2. On first start the CLI automatically downloads the matching **VS Code Server** bundle.
3. Runs `code serve-web` via **supervisor** so it restarts automatically.

## Usage

```jsonc
// .devcontainer/devcontainer.json
{
    "features": {
        "ghcr.io/ricky1698/devcontainer-features/vscode-serve-web:1": {
            "port": "8080",
            "connectionToken": false,
            "extensions": "ms-python.python,eamodio.gitlens"
        }
    }
}
```

Open `http://localhost:8080` (or the forwarded port) in your browser to access VS Code.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `port` | string | `"8080"` | Port the web server listens on |
| `host` | string | `"0.0.0.0"` | Host/interface to bind |
| `connectionToken` | boolean | `false` | `true` = require a token; `false` = `--without-connection-token` |
| `extensions` | string | `""` | Comma-separated extension IDs to pre-install at build time |

## Notes

- Requires `ghcr.io/ricky1698/devcontainer-features/devdesk-base` (provides supervisor).
- Extensions can also be installed at runtime through the VS Code web UI or via `devcontainer.json` `customizations.vscode.extensions`.
- The VS Code Server is cached in `~/.vscode/cli/servers/` and reused across restarts.
- Logs are written to `/var/log/vscode-serve-web.log` and `/var/log/vscode-serve-web.err.log`.
