
# Code Server (code-server)

VS Code in the browser (code-server) with proper entrypoint chaining

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/code-server:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| port | Port for code-server | string | 8888 |
| host | Host to bind code-server | string | 0.0.0.0 |
| auth | Authentication type | string | none |
| version | Version of code-server to install (empty for latest) | string | 4.115.0 |
| extensions | Comma-separated list of VS Code extensions to install | string | - |
| copilot_chat_version | Version of GitHub Copilot Chat extension to install (e.g. 0.43.0). Empty for latest. VSIX is downloaded from github.com/microsoft/vscode-copilot-chat/releases. | string | 0.43.0 |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/code-server/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
