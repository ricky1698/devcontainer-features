
# Nginx Proxy Manager (nginx-proxy-manager)

Nginx Proxy Manager with HTTPS support. Admin UI on port 81, HTTP on port 80, HTTPS on port 443. Each service gets a {name}.localhost subdomain.

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/nginx-proxy-manager:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| services | Comma-separated services in format name:port:description:icon. Each service gets a {name}.localhost subdomain. | string | noVNC:6080:VNC web client:monitor,Code Server:8888:VS Code in browser:terminal |
| adminEmail | NPM admin email address | string | admin@example.com |
| adminPassword | NPM admin password | string | changeme |
| httpsOnly | Force HTTP to HTTPS redirect on all proxy hosts | boolean | false |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/nginx-proxy-manager/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
