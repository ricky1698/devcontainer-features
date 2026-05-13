
# OpenAB Gateway (openab-gateway)

Standalone webhook gateway for openab — bridges Telegram / LINE / Feishu / Google Chat / MS Teams to an outbound-only openab pod over WebSocket. Builds the `openab-gateway` binary from the openab repo's `gateway/` sub-crate.

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/openab-gateway:1": {}
}
```

Building from a fork's branch (e.g. an unmerged feature branch):

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/openab-gateway:1": {
        "version": "feat/my-branch",
        "repoUrl": "https://github.com/<you>/openab.git",
        "autostart": true
    }
}
```

Pair with `openab-broker` for a full broker + gateway stack in the same container:

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/openab-broker:1": {
        "defaultAgent": "claude"
    },
    "ghcr.io/ricky1698/devcontainer-features/openab-gateway:1": {
        "autostart": true
    }
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | openab version to build from. Use `latest` for main, a semver like `0.7.6` (resolved to tag v0.7.6), or any git ref (branch/tag/SHA). | string | latest |
| repoUrl | Git repository URL to clone openab from. Override to point at a fork when building an unmerged branch. | string | https://github.com/openabdev/openab.git |
| listenAddr | `GATEWAY_LISTEN` value — the address openab-gateway binds to. | string | 0.0.0.0:8080 |
| autostart | Start openab-gateway automatically via supervisor when the container boots. Requires at least one platform credential in env. | boolean | false |

## Platform Credentials

The gateway has **no config file** — it is driven entirely by environment variables. Set these in your devcontainer environment, your shell, or your secret store. At least one must be present for the entrypoint hook to auto-start the gateway.

| Variable | Platform |
|-----|-----|
| `TELEGRAM_BOT_TOKEN` | Telegram |
| `LINE_CHANNEL_SECRET` + `LINE_CHANNEL_ACCESS_TOKEN` | LINE |
| `FEISHU_APP_ID` + `FEISHU_APP_SECRET` | Feishu / Lark |
| `GOOGLE_CHAT_ENABLED=true` + `GOOGLE_CHAT_SA_KEY_FILE` (or `GOOGLE_CHAT_SA_KEY_JSON`) | Google Chat |

See the upstream [gateway README](https://github.com/openabdev/openab/blob/main/gateway/README.md) for the full variable list (allowlists, dedupe TTLs, MS Teams, etc.).

## Endpoints

After install, the gateway listens on `listenAddr` (default `0.0.0.0:8080`) and exposes:

| Path | Description |
|-----|-----|
| `POST /webhook/telegram` | Telegram webhook receiver |
| `POST /webhook/line` | LINE webhook receiver |
| `POST /webhook/feishu` | Feishu webhook receiver (when `FEISHU_CONNECTION_MODE=webhook`) |
| `POST /webhook/googlechat` | Google Chat webhook receiver |
| `GET /ws` | WebSocket server (openab pod connects here) |
| `GET /health` | Health check |

## OAB Side

To make the openab broker talk to this gateway, add a `[gateway]` block to the broker's `config.toml`:

```toml
[gateway]
url = "ws://localhost:8080/ws"
platform = "telegram"        # session key namespacing
token = "shared-secret"      # optional WS auth
streaming = true
```

## Manual Install (without devcontainer features)

```bash
sudo bash setup.sh \
    --version latest \
    --listen-addr 0.0.0.0:8080 \
    --autostart
```

---

_Note: This file is hand-maintained alongside [devcontainer-feature.json](./devcontainer-feature.json)._
