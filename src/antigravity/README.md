# Antigravity Remote Control (antigravity)

Antigravity CLI (agy) with its Remote Control daemon supervised by supervisor instead of systemd/launchd

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/antigravity:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| instanceName | Instance name shown in Remote Control (--remote-control-name). Empty = keep whatever the language server has saved, or let it generate one. | string | - |
| autoUpdate | Let agy self-update: runs the background updater before each launch, matching the systemd unit's ExecStartPre. | boolean | true |
| autostart | Start the daemon automatically via supervisor. Needs a completed one-time sign-in (run 'agy-remote-control-login'), otherwise the daemon exits immediately. | boolean | false |

# Notes

This is the `agy --remote-control` daemon that
[`agy-daemon.sh`](https://antigravity.google/docs/remote-control/) normally
installs as a systemd user unit, ported to supervisor so it works in a container
where PID 1 is not systemd.

## What the feature installs

| Path | Purpose |
|------|---------|
| `~/.local/bin/agy` | The CLI itself, via the official installer (sha512-verified, ~200 MB). Kept in `$HOME` because agy rewrites its own binary when it self-updates. |
| `/usr/local/bin/agy-remote-control` | Launcher: runs the background updater, picks a free hub port, then execs `agy --remote-control`. |
| `/usr/local/bin/agy-remote-control-login` | One-time interactive sign-in, then starts the daemon. |
| `/etc/supervisor/conf.d/antigravity.conf` | `[program:antigravity]`. |

## systemd unit → supervisor program

| Unit directive | Supervisor equivalent |
|----------------|-----------------------|
| `ExecStart=run_agy_remote_control.sh` | `command=/usr/local/bin/agy-remote-control` |
| `StandardInput=null` (systemd's default) | supervisor gives the program a pipe it never writes to or closes, and agy blocks on its first read of stdin, so the wrapper does `exec 0</dev/null` before launching. Without it the daemon sits at 0% CPU in `pipe_read` and never binds its hub port |
| `ExecStartPre=-agy --bg-updater` | No pre-start hook exists, so the wrapper runs it under `timeout 60 … \|\| true` before exec'ing the daemon |
| `Restart=always`, `RestartSec=5` | `autorestart=true`, `startsecs=5` |
| `StartLimitIntervalSec=0` (retry forever) | `startretries=3`, deliberately not unlimited — an unauthenticated daemon exits at once, and three tries is enough to see that in `supervisorctl status` instead of a silent crash loop |
| `Environment=AGY_CLI_DISABLE_AUTO_UPDATE=false` | `environment=…,AGY_CLI_DISABLE_AUTO_UPDATE="false"` (flipped by the `autoUpdate` option) |
| `StandardOutput/Error=append:~/.antigravity/agy_daemon.log` | `stdout_logfile=/var/log/antigravity.log`, `stderr_logfile=/var/log/antigravity.err.log`. Both stay nearly empty in practice: agy reopens its own fd 1/2 onto `~/.gemini/antigravity-cli/log/cli-<timestamp>.log`, which is where the real output goes |
| `WantedBy=default.target` | `autostart` option, plus the entrypoint starting it once a token exists |

The upstream auto-update *timer* (a periodic `systemctl --user restart` to pick
up a downloaded update) is not ported. `autorestart=true` already restarts the
daemon whenever it exits, and `--bg-updater` runs on every launch.

## Sign in before it can run

The daemon has no stdin, so the paste-a-code OAuth flow cannot happen under
supervisor. Run it once:

```bash
agy-remote-control-login
```

The token lands in `~/.gemini/jetski-standalone-oauth-token` and the daemon
reuses it across restarts. Until that file exists the entrypoint leaves the
program stopped and says so, rather than letting it crash-loop.

## Hub port

`agy` exits at startup if its local hub port is taken, so the wrapper probes
`AGY_HUB_PORT_START` (default 4400) upward through 100 ports on every launch.
Because it re-probes per launch, two instances on one box settle on different
ports by themselves.

## Operating it

```bash
sudo supervisorctl status antigravity
sudo supervisorctl restart antigravity     # also applies a downloaded update
tail -f ~/.gemini/antigravity-cli/log/cli-*.log   # agy's own log; /var/log/antigravity.log is a fallback
```

Knobs (instance name, hub port, auto-update) live in the `environment=` line of
`/etc/supervisor/conf.d/antigravity.conf`; edit it and
`sudo supervisorctl update` to apply.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/antigravity/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
