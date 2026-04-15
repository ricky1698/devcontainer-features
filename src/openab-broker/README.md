
# OpenAB Broker (openab-broker)

Open Agent Broker (openab) — Discord bot bridging to ACP-enabled coding agents. Builds openab from source; agent CLIs must be provided by other features.

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/openab-broker:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | openab git ref to build (branch, tag, or commit SHA) | string | main |
| repoUrl | Git repository URL to clone openab from | string | https://github.com/openabdev/openab.git |
| defaultAgent | Which agent to wire into the generated config.toml [agent] section | string | copilot |
| configPath | Path where the generated config.toml is written | string | /etc/openab/config.toml |
| allowedChannels | Comma-separated Discord channel IDs allowed to talk to the broker (empty = placeholder) | string | - |
| maxSessions | pool.max_sessions value written into config.toml | string | 10 |
| autostart | Start openab automatically via supervisor. Requires DISCORD_BOT_TOKEN to be set in the container environment. | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/openab-broker/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
