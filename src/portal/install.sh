#!/usr/bin/env bash
set -e

echo "Installing DevDesk Portal..."

TTYD=${TTYD:-"true"}
TTYD_PORT=${TTYD_PORT:-"7681"}

# Install nginx if not present
if ! command -v nginx &> /dev/null; then
    apt-get update
    apt-get install -y nginx
fi

# Install ttyd if enabled
if [ "$TTYD" = "true" ] && ! command -v ttyd &> /dev/null; then
    echo "Installing ttyd..."
    apt-get update 2>/dev/null || true
    apt-get install -y ttyd || {
        # Fallback: download binary for current arch
        ARCH=$(dpkg --print-architecture)
        case "$ARCH" in
            amd64) TTYD_ARCH="x86_64" ;;
            arm64) TTYD_ARCH="aarch64" ;;
            *) echo "Unsupported arch: $ARCH"; exit 1 ;;
        esac
        TTYD_VERSION=$(curl -s https://api.github.com/repos/tsl0922/ttyd/releases/latest | grep tag_name | cut -d'"' -f4)
        curl -fsSL "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" -o /usr/local/bin/ttyd
        chmod +x /usr/local/bin/ttyd
    }
fi

rm -rf /var/lib/apt/lists/*

# If ttyd enabled, auto-append Terminal service to SERVICES
if [ "$TTYD" = "true" ]; then
    if [ -n "$SERVICES" ]; then
        SERVICES="${SERVICES},Terminal:${TTYD_PORT}:Web terminal:terminal"
    else
        SERVICES="Terminal:${TTYD_PORT}:Web terminal:terminal"
    fi
fi

# Create portal directory
mkdir -p /var/www/portal

# Create portal HTML
cat > /var/www/portal/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DevDesk Portal</title>
    <script src="https://cdn.jsdelivr.net/npm/js-yaml@4/dist/js-yaml.min.js"></script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@5.1.0/css/xterm.css">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            color: #fff;
        }
        .portal-content { padding: 2rem; flex-shrink: 0; }
        h1 { text-align: center; margin-bottom: 2rem; font-size: 2rem; color: #e94560; }
        .services {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 1.5rem;
            max-width: 1200px;
            margin: 0 auto;
        }
        .service-card {
            background: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.1);
            border-radius: 12px;
            padding: 1.5rem;
            transition: all 0.3s ease;
            text-decoration: none;
            color: inherit;
            display: block;
            cursor: pointer;
        }
        .service-card:hover {
            background: rgba(255, 255, 255, 0.1);
            transform: translateY(-4px);
            border-color: #e94560;
        }
        .service-header { display: flex; align-items: center; gap: 1rem; margin-bottom: 0.75rem; }
        .service-icon {
            width: 40px; height: 40px;
            background: #e94560;
            border-radius: 8px;
            display: flex; align-items: center; justify-content: center;
            font-size: 1.25rem;
        }
        .service-name { font-size: 1.25rem; font-weight: 600; }
        .service-desc { color: rgba(255, 255, 255, 0.7); font-size: 0.9rem; margin-bottom: 0.75rem; }
        .service-port {
            font-family: monospace;
            background: rgba(233, 69, 96, 0.2);
            color: #e94560;
            padding: 0.25rem 0.5rem;
            border-radius: 4px;
            font-size: 0.85rem;
            display: inline-block;
        }
        .loading { text-align: center; padding: 2rem; color: rgba(255, 255, 255, 0.6); }
        .error { text-align: center; padding: 2rem; color: #e94560; }

        /* Terminal panel */
        #terminal-panel {
            display: none;
            flex: 1;
            flex-direction: column;
            border-top: 2px solid #e94560;
            min-height: 0;
        }
        #terminal-panel.open { display: flex; }
        .term-toolbar {
            display: flex;
            align-items: center;
            gap: 0.75rem;
            padding: 0.5rem 1rem;
            background: rgba(0, 0, 0, 0.4);
            border-bottom: 1px solid rgba(255, 255, 255, 0.1);
            font-size: 0.85rem;
        }
        .term-toolbar .term-title { flex: 1; color: #e94560; font-weight: 600; }
        .term-toolbar .term-status { font-size: 0.75rem; color: rgba(255, 255, 255, 0.5); }
        .btn-term-close {
            background: rgba(233, 69, 96, 0.2);
            border: 1px solid rgba(233, 69, 96, 0.3);
            color: #e94560;
            font-size: 0.8rem;
            padding: 0.25rem 0.75rem;
            border-radius: 4px;
            cursor: pointer;
        }
        .btn-term-close:hover { background: rgba(233, 69, 96, 0.4); }
        #terminal-container {
            flex: 1;
            padding: 4px;
            background: #000;
            min-height: 300px;
        }
        #terminal-container .xterm { height: 100%; }
    </style>
</head>
<body>
    <div class="portal-content">
        <h1>DevDesk Portal</h1>
        <div id="services" class="services">
            <div class="loading">Loading services...</div>
        </div>
        <div id="links-section" style="display: none; margin-top: 3rem;">
            <h2 style="text-align: center; margin-bottom: 1.5rem; font-size: 1.5rem; color: #e94560;">Direct Links</h2>
            <div id="links" class="services">
                <div class="loading">Loading links...</div>
            </div>
        </div>
    </div>

    <!-- Terminal panel -->
    <div id="terminal-panel">
        <div class="term-toolbar">
            <span class="term-title" id="term-title">Terminal</span>
            <span class="term-status" id="term-status"></span>
            <button class="btn-term-close" id="term-close">Close</button>
        </div>
        <div id="terminal-container"></div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/xterm@5.1.0/lib/xterm.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.7.0/lib/xterm-addon-fit.js"></script>
    <script>
        const icons = { code: '💻', globe: '🌐', monitor: '🖥️', bot: '🤖', terminal: '⌨️', default: '🔧' };

        // --- Terminal (ttyd protocol) ---
        const TTYD_OUTPUT = '0';
        const TTYD_SET_TITLE = '1';
        const TTYD_SET_PREFS = '2';
        const TTYD_INPUT = '0';
        const TTYD_RESIZE = '1';

        let term = null;
        let termSocket = null;
        let fitAddon = null;

        function openTerminal(wsPath, title) {
            closeTerminal();
            const panel = document.getElementById('terminal-panel');
            panel.classList.add('open');
            document.getElementById('term-title').textContent = title || 'Terminal';
            document.getElementById('term-status').textContent = 'Connecting...';

            term = new Terminal({
                cursorBlink: true,
                fontSize: 14,
                fontFamily: "Consolas, 'Liberation Mono', Menlo, monospace",
                theme: { background: '#000000', foreground: '#e2e8f0' },
            });
            fitAddon = new FitAddon.FitAddon();
            term.loadAddon(fitAddon);
            term.open(document.getElementById('terminal-container'));
            fitAddon.fit();

            const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = protocol + '//' + location.host + wsPath;

            termSocket = new WebSocket(wsUrl, ['tty']);

            termSocket.onopen = () => {
                termSocket.send(JSON.stringify({ AuthToken: '' }));
                document.getElementById('term-status').textContent = 'Connected';
                term.focus();
                setTimeout(() => sendResize(), 100);
            };

            termSocket.onmessage = (evt) => {
                const raw = evt.data;
                if (raw instanceof Blob) {
                    raw.text().then(handleMsg);
                } else {
                    handleMsg(raw);
                }
            };

            function handleMsg(data) {
                if (!data || data.length === 0) return;
                const type = data[0], payload = data.slice(1);
                switch (type) {
                    case TTYD_OUTPUT: term.write(payload); break;
                    case TTYD_SET_TITLE:
                        document.getElementById('term-title').textContent = payload || title;
                        break;
                    case TTYD_SET_PREFS: break;
                }
            }

            termSocket.onclose = (evt) => {
                document.getElementById('term-status').textContent = 'Disconnected (code: ' + evt.code + ')';
                term.write('\r\n\x1b[90m--- connection closed ---\x1b[0m\r\n');
            };

            termSocket.onerror = () => {
                document.getElementById('term-status').textContent = 'Connection failed';
                term.write('\r\n\x1b[31mFailed to connect to terminal.\x1b[0m\r\n');
            };

            term.onData((data) => {
                if (termSocket && termSocket.readyState === WebSocket.OPEN) {
                    termSocket.send(TTYD_INPUT + data);
                }
            });

            function sendResize() {
                if (termSocket && termSocket.readyState === WebSocket.OPEN && term) {
                    termSocket.send(TTYD_RESIZE + JSON.stringify({ columns: term.cols, rows: term.rows }));
                }
            }

            term.onResize(({ cols, rows }) => {
                if (termSocket && termSocket.readyState === WebSocket.OPEN) {
                    termSocket.send(TTYD_RESIZE + JSON.stringify({ columns: cols, rows: rows }));
                }
            });

            const resizeObs = new ResizeObserver(() => { if (fitAddon) fitAddon.fit(); });
            resizeObs.observe(document.getElementById('terminal-container'));
            term._resizeObs = resizeObs;
        }

        function closeTerminal() {
            if (termSocket) { termSocket.close(); termSocket = null; }
            if (term) {
                if (term._resizeObs) term._resizeObs.disconnect();
                term.dispose();
                term = null;
            }
            fitAddon = null;
            document.getElementById('terminal-panel').classList.remove('open');
            document.getElementById('terminal-container').innerHTML = '';
        }

        document.getElementById('term-close').addEventListener('click', closeTerminal);

        // --- Services ---
        async function loadServices() {
            const container = document.getElementById('services');
            try {
                const response = await fetch('/services.yaml');
                const text = await response.text();
                const data = jsyaml.load(text);
                container.innerHTML = '';
                data.services.forEach(service => {
                    const path = service.name.toLowerCase().replace(/\s+/g, '-');
                    const isTerminal = service.icon === 'terminal';
                    const card = document.createElement('a');
                    card.className = 'service-card';
                    if (isTerminal) {
                        card.href = '#';
                        card.addEventListener('click', (e) => {
                            e.preventDefault();
                            openTerminal('/' + path + '/ws', service.name);
                        });
                    } else {
                        card.href = '/' + path + '/';
                        card.target = '_blank';
                    }
                    card.innerHTML =
                        '<div class="service-header">' +
                            '<div class="service-icon">' + (icons[service.icon] || icons.default) + '</div>' +
                            '<div class="service-name">' + service.name + '</div>' +
                        '</div>' +
                        '<div class="service-desc">' + service.description + '</div>' +
                        '<span class="service-port">/' + path + '/</span>';
                    container.appendChild(card);
                });
            } catch (err) {
                container.innerHTML = '<div class="error">Failed to load services: ' + err.message + '</div>';
            }
        }

        async function loadLinks() {
            const container = document.getElementById('links');
            const section = document.getElementById('links-section');
            try {
                const response = await fetch('/links.yaml');
                if (!response.ok) { section.style.display = 'none'; return; }
                const text = await response.text();
                const data = jsyaml.load(text);
                if (!data || !data.links || data.links.length === 0) {
                    section.style.display = 'none';
                    return;
                }
                section.style.display = 'block';
                container.innerHTML = '';
                data.links.forEach(link => {
                    const card = document.createElement('a');
                    card.className = 'service-card';
                    card.href = 'http://' + window.location.hostname + ':' + link.port;
                    card.target = '_blank';
                    card.innerHTML =
                        '<div class="service-header">' +
                            '<div class="service-icon">' + (icons[link.icon] || icons.default) + '</div>' +
                            '<div class="service-name">' + link.name + '</div>' +
                        '</div>' +
                        '<div class="service-desc">' + link.description + '</div>' +
                        '<span class="service-port">' + window.location.hostname + ':' + link.port + '</span>';
                    container.appendChild(card);
                });
            } catch (err) {
                section.style.display = 'none';
            }
        }

        loadServices();
        loadLinks();
    </script>
</body>
</html>
HTMLEOF

# Create services.yaml from SERVICES parameter
# Format: name:port:description:icon[:passthrough]
#   passthrough=true  → nginx keeps the path prefix (required for apps that use --server-base-path)
#   passthrough=false → nginx strips the path prefix (default, for apps that serve from /)
echo "services:" > /var/www/portal/services.yaml

IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICES"
for service in "${SERVICE_ARRAY[@]}"; do
    IFS=':' read -r name port desc icon passthrough <<< "$service"
    cat >> /var/www/portal/services.yaml << SERVICEEOF
  - name: $name
    port: $port
    description: $desc
    icon: $icon

SERVICEEOF
done

# Create links.yaml from LINKS parameter (for services that don't work behind reverse proxy)
# Format: name:port:description:icon,name:port:description:icon,...
if [ -n "$LINKS" ]; then
    echo "links:" > /var/www/portal/links.yaml
    IFS=',' read -ra LINK_ARRAY <<< "$LINKS"
    for link in "${LINK_ARRAY[@]}"; do
        IFS=':' read -r name port desc icon <<< "$link"
        cat >> /var/www/portal/links.yaml << LINKEOF
  - name: $name
    port: $port
    description: $desc
    icon: $icon

LINKEOF
    done
else
    # Create empty links.yaml
    echo "links: []" > /var/www/portal/links.yaml
fi

# Add a map so nginx passes the upstream X-Forwarded-Proto through correctly.
# When behind a TLS-terminating proxy, $http_x_forwarded_proto is "https";
# when accessed directly over HTTP it falls back to $scheme.
cat > /etc/nginx/conf.d/forwarded-proto.conf << 'MAPEOF'
# Pass upstream TLS-terminator's proto through; fall back to $scheme for direct HTTP.
map $http_x_forwarded_proto $real_forwarded_proto {
    default $scheme;
    https   https;
}

# Correctly handle both WebSocket upgrades and plain HTTP connections.
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
MAPEOF

# Create nginx config as reverse proxy
cat > /etc/nginx/sites-available/portal << NGINXEOF
server {
    listen 80;
    server_name localhost;

    # Portal UI - serve static files
    location / {
        root /var/www/portal;
        index index.html;
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(yaml|yml)$ {
        root /var/www/portal;
        add_header Content-Type text/yaml;
    }
NGINXEOF

# Add reverse proxy locations for each service
IFS=',' read -ra SERVICE_ARRAY <<< "$SERVICES"
for service in "${SERVICE_ARRAY[@]}"; do
    IFS=':' read -r name port desc icon passthrough <<< "$service"
    # Create a URL-safe path from service name (lowercase, replace spaces with hyphens)
    path=$(tr '[:upper:]' '[:lower:]' <<< "$name" | sed 's/[[:space:]]\+/-/g')

    # passthrough=true → keep path prefix (for apps using --server-base-path)
    # passthrough=false/empty → strip path prefix (default, for apps serving from /)
    if [[ "$passthrough" == "true" ]]; then
        proxy_target="http://localhost:$port/$path/"
    else
        proxy_target="http://localhost:$port/"
    fi

    cat >> /etc/nginx/sites-available/portal << PROXYEOF

    # Reverse proxy for $name (passthrough=$passthrough)
    location /$path/ {
        proxy_pass $proxy_target;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$real_forwarded_proto;
        proxy_buffering off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
PROXYEOF
done

cat >> /etc/nginx/sites-available/portal << 'NGINXEOF'
}
NGINXEOF

# Enable the site
ln -sf /etc/nginx/sites-available/portal /etc/nginx/sites-enabled/portal
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Create supervisor config for nginx
mkdir -p /etc/supervisor/conf.d
cat > /etc/supervisor/conf.d/nginx.conf << 'SUPERVISOREOF'
[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/var/log/nginx-supervisor.log
stderr_logfile=/var/log/nginx-supervisor.err.log
SUPERVISOREOF

# Create supervisor config for ttyd if enabled
if [ "$TTYD" = "true" ]; then
    TTYD_BIN=$(command -v ttyd)
    cat > /etc/supervisor/conf.d/ttyd.conf << TTYDEOF
[program:ttyd]
command=${TTYD_BIN} -W -p ${TTYD_PORT} -i 127.0.0.1 zsh
autostart=true
autorestart=true
stdout_logfile=/var/log/ttyd-supervisor.log
stderr_logfile=/var/log/ttyd-supervisor.err.log
user=$_REMOTE_USER
directory=$_REMOTE_USER_HOME
environment=HOME="$_REMOTE_USER_HOME",USER="$_REMOTE_USER"
TTYDEOF
fi

# Create entrypoint script
cat > /usr/local/bin/devdesk-portal-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Ensure supervisord is running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Reload supervisor to pick up all configs
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start all 2>/dev/null || true

# Execute the next command in the chain
exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-portal-entrypoint

echo "DevDesk Portal installation complete! (port 80 - reverse proxy)"
