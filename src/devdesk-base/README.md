
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
| packages | Comma-separated list of mise packages to install (format: name@version) | string | bun@1,eza@latest,fd@10,fzf@0.61,gh@latest,lazygit@latest,just@1,neovim@latest,node@lts,pnpm@latest,pre-commit@latest,rg@14,tmux@3,uv@latest,yazi@latest,zoxide@latest,kubectl@1,helm@3,k9s@latest,kind@latest,mprocs@latest,rust@latest,dotnet@10 |
| npmGlobalPackages | Comma-separated list of npm global packages to install | string | @playwright/cli@latest |
| cargoPackages | Comma-separated list of cargo packages to install (e.g. cargo-watch,tokei) | string | worktrunk |
| extraPackages | Extra mise packages to install on top of defaults (format: name@version) | string | - |
| extraNpmGlobalPackages | Extra npm global packages to install on top of defaults | string | - |
| extraCargoPackages | Extra cargo packages to install on top of defaults | string | - |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/devdesk-base/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
