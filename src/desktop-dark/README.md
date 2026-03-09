
# Desktop (Dark Theme) (desktop-dark)

Lightweight Fluxbox desktop with dark theme, accessible via VNC viewer or web browser. Based on devcontainers/features/desktop-lite with built-in dark mode support.

## Example Usage

```json
"features": {
    "ghcr.io/ricky1698/devcontainer-features/desktop-dark:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| noVncVersion | The noVNC version to use | string | 1.6.0 |
| password | Desktop connection password. Use "noPassword" for localhost-only access without authentication | string | vscode |
| webPort | Port for the VNC web client (noVNC) | string | 6080 |
| vncPort | Port for the desktop VNC server (TigerVNC) | string | 5901 |
| backgroundColor | Desktop background color (hex) | string | #1E1E1E |
| gtkTheme | GTK theme name for applications | string | Adwaita-dark |
| gtkIconTheme | GTK icon theme name | string | Adwaita |



---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/ricky1698/devcontainer-features/blob/main/src/desktop-dark/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
