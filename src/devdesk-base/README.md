
# DevDesk Base (devdesk-base)

Base development environment with mise, common CLI tools, and supervisor

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/devdesk-base:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| installMise | Install mise (runtime manager) | boolean | true |
| installSupervisor | Install supervisor process manager | boolean | true |
| packages | Comma-separated list of mise packages to install (format: name@version) | string | bun@1,eza@latest,fd@10,fzf@0.61,gh@latest,lazygit@latest,just@1,neovim@latest,node@lts,pre-commit@latest,rg@14,tmux@3,uv@latest,yazi@latest,zoxide@latest,kubectl@1,helm@3,claude@latest |
| npmGlobalPackages | Comma-separated list of npm global packages to install | string | node-pty,vibetunnel@1.0.0-beta.15.2 |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/devdesk-base/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
