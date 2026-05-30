#!/usr/bin/env bash
set -e

echo "Installing T3Code..."

# Install t3 globally via mise npm
MISE_BIN="$_REMOTE_USER_HOME/.local/bin/mise"
su - "$_REMOTE_USER" -c "$MISE_BIN exec node@lts -- npm install -g t3"

# Ensure supervisor config directory exists
mkdir -p /etc/supervisor/conf.d

# Create supervisor config
AUTOSTART_VALUE="false"
if [[ "$AUTOSTART" == "true" ]]; then
    AUTOSTART_VALUE="true"
fi

cat > /etc/supervisor/conf.d/t3code.conf << CONFEOF
[program:t3code]
command=$_REMOTE_USER_HOME/.local/share/mise/shims/t3 --host $HOSTNAME --no-browser
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=5
autorestart=true
startretries=3
stderr_logfile=/var/log/t3code.err.log
stdout_logfile=/var/log/t3code.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME",NODE_OPTIONS="--no-network-family-autoselection"
CONFEOF

# --- T3 Pairing API Server ---
# A lightweight HTTP server that generates t3 pairing tokens via CLI.
# Runs on localhost:7691, proxied by nginx at /api/t3-pair (if portal feature is installed).

cat > /usr/local/bin/t3-pair-server << 'T3PAIREOF'
#!/usr/bin/env node
const http = require("http");
const { execSync } = require("child_process");

const PORT = 7691;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Content-Type": "application/json",
};

const server = http.createServer((req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, CORS_HEADERS);
    res.end();
    return;
  }

  if (req.method !== "GET") {
    res.writeHead(405, CORS_HEADERS);
    res.end(JSON.stringify({ error: "Method not allowed" }));
    return;
  }

  try {
    // Get Tailscale FQDN (trim trailing dot)
    const tsStatus = JSON.parse(
      execSync("tailscale status --json", { encoding: "utf-8", timeout: 5000 })
    );
    const fqdn = tsStatus.Self.DNSName.replace(/\.$/, "");

    // Generate pairing token via CLI
    const result = execSync(
      `t3 auth pairing create --json --base-url "http://${fqdn}:3773"`,
      { encoding: "utf-8", timeout: 10000 }
    );

    res.writeHead(200, CORS_HEADERS);
    res.end(result);
  } catch (err) {
    const message = err.stderr || err.message || "Unknown error";
    console.error("t3-pair-server error:", message);
    res.writeHead(500, CORS_HEADERS);
    res.end(JSON.stringify({ error: message }));
  }
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`t3-pair-server listening on http://127.0.0.1:${PORT}`);
});
T3PAIREOF

chmod +x /usr/local/bin/t3-pair-server

# Create supervisor config for pairing server
cat > /etc/supervisor/conf.d/t3-pair-server.conf << PAIREOF
[program:t3-pair-server]
command=$_REMOTE_USER_HOME/.local/share/mise/shims/node /usr/local/bin/t3-pair-server
directory=$_REMOTE_USER_HOME
autostart=$AUTOSTART_VALUE
startsecs=3
autorestart=true
startretries=3
stderr_logfile=/var/log/t3-pair-server.err.log
stdout_logfile=/var/log/t3-pair-server.log
user=$_REMOTE_USER
environment=PATH="$_REMOTE_USER_HOME/.local/bin:$_REMOTE_USER_HOME/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin",HOME="$_REMOTE_USER_HOME"
PAIREOF

# --- Register with portal nginx (if portal feature is installed) ---
if [ -f /etc/nginx/sites-available/portal ]; then
    echo "Registering t3-pair API with portal nginx..."
    # Remove the closing } of the server block, append t3-pair location, re-add }
    sed -i '$ d' /etc/nginx/sites-available/portal
    cat >> /etc/nginx/sites-available/portal << 'NGINXT3EOF'

    # T3 Code pairing API (added by t3code feature)
    location /api/t3-pair {
        proxy_pass http://localhost:7691/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_hide_header Access-Control-Allow-Origin;
        proxy_hide_header Access-Control-Allow-Methods;
        proxy_hide_header Access-Control-Allow-Headers;
        add_header Access-Control-Allow-Origin $http_origin always;
        add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type" always;
        add_header Vary "Origin" always;
        if ($request_method = OPTIONS) { return 204; }
    }
}
NGINXT3EOF
fi

# --- T3 tmp cleaner ---
# t3's provider.session.reaper sweeps every 5 min and spawns `opencode`, which
# uses OpenTUI. OpenTUI extracts an ~8MB libopentui.so to /tmp and dlopen()s it
# but never unlinks it, so each probe leaks one orphan (~2.3GB/day) and fills
# /tmp. This sweeper purges those orphans. Only files untouched for >= min-age
# minutes are removed, so a temp file just written (and possibly still open) is
# left alone. Knobs are overridable via the supervisor config's environment.

cat > /usr/local/bin/t3-tmp-cleaner << 'CLEANEREOF'
#!/usr/bin/env bash
set -u

DIR="${T3_TMP_CLEANER_DIR:-/tmp}"
PATTERN="${T3_TMP_CLEANER_PATTERN:-.*-00000000.so}"
INTERVAL="${T3_TMP_CLEANER_INTERVAL:-600}"
MIN_AGE_MIN="${T3_TMP_CLEANER_MIN_AGE_MIN:-5}"

echo "t3-tmp-cleaner: dir=$DIR pattern='$PATTERN' interval=${INTERVAL}s min_age=${MIN_AGE_MIN}min"

while :; do
    mapfile -t victims < <(find "$DIR" -maxdepth 1 -type f -name "$PATTERN" -mmin +"$MIN_AGE_MIN" 2>/dev/null)
    if [ "${#victims[@]}" -gt 0 ]; then
        printf '%s\0' "${victims[@]}" | xargs -0 rm -f 2>/dev/null || true
        echo "[$(date '+%F %T')] t3-tmp-cleaner: removed ${#victims[@]} file(s) matching '$PATTERN' in $DIR"
    fi
    sleep "$INTERVAL"
done
CLEANEREOF

chmod +x /usr/local/bin/t3-tmp-cleaner

# Create supervisor config for tmp cleaner
cat > /etc/supervisor/conf.d/t3-tmp-cleaner.conf << CLEANERCONFEOF
[program:t3-tmp-cleaner]
command=/usr/local/bin/t3-tmp-cleaner
directory=/
autostart=$AUTOSTART_VALUE
startsecs=3
autorestart=true
startretries=3
stderr_logfile=/var/log/t3-tmp-cleaner.err.log
stdout_logfile=/var/log/t3-tmp-cleaner.log
user=root
CLEANERCONFEOF

# Create entrypoint script
cat > /usr/local/bin/devdesk-t3code-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Reload supervisor to pick up t3code config
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start t3code 2>/dev/null || true
sudo supervisorctl start t3-pair-server 2>/dev/null || true
sudo supervisorctl start t3-tmp-cleaner 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-t3code-entrypoint

echo "T3Code installation complete!"
