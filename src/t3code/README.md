
# T3Code (t3code)

T3Code AI-powered code editor with supervisor config, pairing API, and a /tmp cleaner for OpenTUI temp-file leaks

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/t3code:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| hostname | Hostname to bind T3Code server | string | 0.0.0.0 |
| autostart | Start T3Code automatically via supervisor | boolean | true |

# Notes

This feature installs three supervisor programs:

| Program | Purpose |
|---------|---------|
| `t3code` | The T3 Code server (`t3 --host … --no-browser`), port 3773. |
| `t3-pair-server` | Tiny HTTP helper (localhost:7691) that mints t3 pairing tokens; proxied by the portal nginx at `/api/t3-pair`. |
| `t3-tmp-cleaner` | Periodic `/tmp` sweeper (see below). |

## Why `t3-tmp-cleaner` exists

t3's `provider.session.reaper` sweeps every 5 minutes (`sweepIntervalMs: 300000`)
and spawns `opencode --version` / `opencode serve` to probe the opencode provider.
`opencode` is built on **OpenTUI**, whose native loader extracts an ~8 MB
`libopentui.so` (aarch64, with an embedded `miniaudio`) to
`/tmp/.bdba<hex>-00000000.so`, `dlopen()`s it, and **never unlinks it**. So every
5-minute probe leaks one orphan file — roughly **2.3 GB/day** — until `/tmp` fills.

This is a benign temp-file leak (not malware): every leaked file is byte-for-byte
identical, owned by the dev user, and held open by no process.

`t3-tmp-cleaner` wakes every `T3_TMP_CLEANER_INTERVAL` seconds (default 600) and
deletes files in `T3_TMP_CLEANER_DIR` (default `/tmp`) matching
`T3_TMP_CLEANER_PATTERN` (default `.bdba*.so`) that are older than
`T3_TMP_CLEANER_MIN_AGE_MIN` minutes (default 5). The age guard means a temp file
that was just written (and may still be mid-`dlopen`) is never removed. Tune the
knobs in `/etc/supervisor/conf.d/t3-tmp-cleaner.conf`.

```bash
tail -f /var/log/t3-tmp-cleaner.log     # watch it work
ls /tmp/.bdba*.so 2>/dev/null | wc -l   # current orphan count
```

## Real fix (upstream)

The proper fix belongs in OpenTUI/Bun: `unlink()` the temp `.so` right after
`dlopen()` (on Linux the inode stays valid until `dlclose()`), or reuse a single
cached path instead of writing a fresh randomly-named copy every run. Until then,
this cleaner is the safe, non-invasive mitigation.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/t3code/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
