
# VS Code Serve Web (vscode-serve-web)

Official Microsoft VS Code in the browser using 'code serve-web' with proper entrypoint chaining

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/vscode-serve-web:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| port | Port for VS Code web server | string | 8080 |
| host | Host to bind VS Code web server | string | 0.0.0.0 |
| connectionToken | Require a connection token for authentication (false = --without-connection-token) | boolean | false |
| extensions | Comma-separated list of VS Code extension IDs to pre-install (e.g. ms-python.python,eamodio.gitlens) | string | - |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/vscode-serve-web/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
