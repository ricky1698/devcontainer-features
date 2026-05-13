
# OpenAB Gateway (openab-gateway)

Standalone webhook gateway for openab — bridges Telegram / LINE / Feishu / Google Chat / MS Teams to an outbound-only openab pod over WebSocket. Builds the openab-gateway binary from the openab repo's gateway/ sub-crate.

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/openab-gateway:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | openab version to build from. Use 'latest' for main, a semver like '0.7.6' (resolved to tag v0.7.6), or any git ref (branch/tag/SHA). | string | latest |
| repoUrl | Git repository URL to clone openab from. Override to point at a fork (e.g. https://github.com/<you>/openab.git) when building an unmerged branch. | string | https://github.com/openabdev/openab.git |
| listenAddr | GATEWAY_LISTEN value — the address openab-gateway binds to. | string | 0.0.0.0:8080 |
| autostart | Start openab-gateway automatically via supervisor when the container boots. Requires at least one platform credential in env (TELEGRAM_BOT_TOKEN, FEISHU_APP_ID, GOOGLE_CHAT_ENABLED=true, LINE_CHANNEL_SECRET, ...). | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/openab-gateway/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
