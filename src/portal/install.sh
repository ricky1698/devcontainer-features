#!/usr/bin/env bash
set -e

echo "Installing DevDesk Portal..."

# Install nginx if not present
if ! command -v nginx &> /dev/null; then
    apt-get update
    apt-get install -y nginx
    rm -rf /var/lib/apt/lists/*
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
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            padding: 2rem;
            color: #fff;
        }
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
    </style>
</head>
<body>
    <h1>DevDesk Portal</h1>
    <div id="services" class="services">
        <div class="loading">Loading services...</div>
    </div>
    <script>
        const icons = { code: '💻', globe: '🌐', monitor: '🖥️', bot: '🤖', terminal: '⌨️', default: '🔧' };
        async function loadServices() {
            const container = document.getElementById('services');
            try {
                const response = await fetch('/services.yaml');
                const text = await response.text();
                const data = jsyaml.load(text);
                container.innerHTML = '';
                data.services.forEach(service => {
                    const card = document.createElement('a');
                    card.className = 'service-card';
                    card.href = `http://${location.hostname}:${service.port}`;
                    card.target = '_blank';
                    card.innerHTML = `
                        <div class="service-header">
                            <div class="service-icon">${icons[service.icon] || icons.default}</div>
                            <div class="service-name">${service.name}</div>
                        </div>
                        <div class="service-desc">${service.description}</div>
                        <span class="service-port">:${service.port}</span>
                    `;
                    container.appendChild(card);
                });
            } catch (err) {
                container.innerHTML = `<div class="error">Failed to load services: ${err.message}</div>`;
            }
        }
        loadServices();
    </script>
</body>
</html>
HTMLEOF

# Create default services.yaml
cat > /var/www/portal/services.yaml << 'YAMLEOF'
services:
  - name: noVNC
    port: 6080
    description: VNC web client
    icon: monitor

  - name: Code Server
    port: CODESERVERPORT_PLACEHOLDER
    description: VS Code in browser
    icon: terminal
YAMLEOF

# Replace placeholder with actual port
sed -i "s/CODESERVERPORT_PLACEHOLDER/$CODESERVERPORT/" /var/www/portal/services.yaml

# Create nginx config
cat > /etc/nginx/sites-available/portal << NGINXEOF
server {
    listen $PORT;
    server_name localhost;

    root /var/www/portal;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(yaml|yml)\$ {
        add_header Content-Type text/yaml;
    }
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

echo "DevDesk Portal installation complete! (port $PORT)"
