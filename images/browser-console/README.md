# Browser console image

A cluster-neutral, single-user browser desktop with Chromium, Fluxbox,
TigerVNC, noVNC, and websockify.

The image contains no cluster names, internal hostnames, private certificate
authorities, or credentials. Cluster-specific deployment and access controls
belong in each infrastructure repository.

## Runtime interface

| Input | Required | Behavior |
|---|---|---|
| `/run/secrets/vnc/password` | Yes | An eight-character visible ASCII VNC password |
| `BROWSER_START_URL` | No | Chromium start page, defaults to `about:blank` |
| `BROWSER_CA_FILE` | No | Path to a PEM-encoded cluster CA |
| `/etc/chromium/policies/managed` | With a custom CA | Writable volume used for the generated `CACertificates` policy |
| `/home/browser`, `/run/browser-console`, `/tmp`, `/dev/shm` | Yes | Writable runtime volumes for a read-only root filesystem |

The image exposes TCP 6080. TigerVNC listens only on container loopback TCP
5901. A cluster adapter must provide authentication, network policy, service,
and ingress behavior.

## Cluster adapter

Do not modify the image when adding a cluster. Its adapter must:

1. Set `BROWSER_START_URL`.
2. Provide internal hostname resolution through cluster DNS or `hostAliases`.
3. Mount a VNC password Secret outside Git.
4. If needed, mount the public CA, set `BROWSER_CA_FILE`, and provide a writable
   Chromium policy directory. A CA change must also restart the Pod.
5. Provide deployment and live verification through that cluster's existing
   resource owner.

The adapter may use direct `kubectl apply`, Helm, or GitOps, but a resource must
have exactly one owner.

## Local verification

```bash
docker build -t browser-console:test images/browser-console
uv run images/browser-console/smoke-test.py --image browser-console:test
```

The smoke test covers startup with and without a custom CA, noVNC, WebSocket,
VNC authentication, framebuffer output, Chromium policy, sandboxing, and
container exit after Chromium stops. It also runs repeated health checks before
VNC authentication to prevent probes from triggering TigerVNC's connection
blacklist.

## Published image

Merges to `main` publish these tags:

- `ghcr.io/ricky1698/devcontainer-features/browser-console:1.0.1`
- `ghcr.io/ricky1698/devcontainer-features/browser-console:latest`
- `ghcr.io/ricky1698/devcontainer-features/browser-console:sha-<commit>`

Bump `VERSION` before changing the image after a release.

GHCR packages are private when first created. After the first publish, set the
`browser-console` package visibility to public once so clusters can pull it
without an image pull Secret.
