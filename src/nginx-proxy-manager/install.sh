#!/usr/bin/env bash
set -e

echo "Installing Nginx Proxy Manager..."

# --- 1. System dependencies ---
apt-get update
apt-get install -y nginx openssl curl python3
rm -rf /var/lib/apt/lists/*

# --- 2. Find Node.js from mise shims ---
NODE_BIN="$_REMOTE_USER_HOME/.local/share/mise/shims/node"
if [ ! -x "$NODE_BIN" ]; then
    NODE_BIN=$(command -v node 2>/dev/null || echo "")
fi
if [ -z "$NODE_BIN" ]; then
    echo "ERROR: Node.js not found. Install Node.js via mise (devdesk-base feature) first."
    exit 1
fi

NPM_CLI="$(dirname "$NODE_BIN")/npm"
NODE_PATH="$(dirname "$NODE_BIN")"
echo "Using Node.js: $NODE_BIN"

# --- 3. Get latest NPM release ---
echo "Fetching latest Nginx Proxy Manager version..."
NPM_VERSION=$(curl -sf "https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest" | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))")
echo "Installing Nginx Proxy Manager v${NPM_VERSION}..."

# --- 4. Download and extract ---
TMPDIR=$(mktemp -d)
curl -fL \
    "https://github.com/NginxProxyManager/nginx-proxy-manager/releases/download/v${NPM_VERSION}/npm-${NPM_VERSION}.tar.gz" \
    -o "$TMPDIR/npm.tar.gz"

mkdir -p /opt/nginx-proxy-manager

# Detect tarball structure and extract accordingly
TOPLEVEL=$(tar tzf "$TMPDIR/npm.tar.gz" | head -1 | cut -d/ -f1)
if tar tzf "$TMPDIR/npm.tar.gz" | grep -q "^${TOPLEVEL}/backend/"; then
    tar xzf "$TMPDIR/npm.tar.gz" -C /opt/nginx-proxy-manager --strip-components=1
else
    tar xzf "$TMPDIR/npm.tar.gz" -C /opt/nginx-proxy-manager
fi
rm -rf "$TMPDIR"

# --- 5. Install backend Node.js dependencies ---
echo "Installing backend dependencies..."
cd /opt/nginx-proxy-manager/backend
"$NPM_CLI" install --production 2>&1 | tail -5

# --- 6. Set up data directories ---
mkdir -p \
    /data/nginx/default_host \
    /data/nginx/proxy_host \
    /data/nginx/redirection_host \
    /data/nginx/dead_host \
    /data/nginx/stream \
    /data/nginx/temp \
    /data/custom_ssl \
    /data/logs \
    /data/access \
    /data/letsencrypt-acme-challenge \
    /etc/letsencrypt

# --- 7. Configure nginx to include NPM-generated configs ---
# Remove default site to avoid conflicts
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/nginx.conf << 'NGINXEOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
}

http {
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log warn;

    # NPM generated proxy host configurations
    include /data/nginx/proxy_host/*.conf;
    include /data/nginx/redirection_host/*.conf;
    include /data/nginx/default_host/*.conf;
    include /data/nginx/dead_host/*.conf;
}
NGINXEOF

# Test nginx config
nginx -t 2>/dev/null || true

# --- 8. Save services config for entrypoint ---
cat > /etc/devdesk-npm.env << ENVEOF
NPM_SERVICES="${SERVICES}"
NPM_ADMIN_EMAIL="${ADMIN_EMAIL}"
NPM_ADMIN_PASSWORD="${ADMIN_PASSWORD}"
NPM_HTTPS_ONLY="${HTTPS_ONLY}"
ENVEOF

# --- 9. Supervisor configs ---
mkdir -p /etc/supervisor/conf.d

cat > /etc/supervisor/conf.d/nginx-proxy-manager.conf << SUPERVISOREOF
[program:nginx-proxy-manager]
command=${NODE_BIN} /opt/nginx-proxy-manager/backend/index.js
directory=/opt/nginx-proxy-manager/backend
autostart=true
autorestart=true
startretries=5
startsecs=15
stderr_logfile=/var/log/npm-backend.err.log
stdout_logfile=/var/log/npm-backend.log
environment=NODE_ENV="production",DB_SQLITE_FILE="/data/database.sqlite",DISABLE_IPV6="true",TZ="UTC",HOME="${_REMOTE_USER_HOME}",PATH="${NODE_PATH}:/usr/local/bin:/usr/bin:/bin"
SUPERVISOREOF

cat > /etc/supervisor/conf.d/npm-nginx.conf << 'SUPERVISOREOF'
[program:npm-nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=true
autorestart=true
startretries=3
startsecs=5
stderr_logfile=/var/log/npm-nginx.err.log
stdout_logfile=/var/log/npm-nginx.log
SUPERVISOREOF

# --- 10. Entrypoint script ---
cat > /usr/local/bin/devdesk-npm-entrypoint << 'ENTRYPOINTEOF'
#!/bin/bash

# Start supervisord if not running
if ! pgrep -x supervisord > /dev/null; then
    echo "→ Starting supervisord..."
    sudo supervisord -c /etc/supervisor/supervisord.conf
fi

# Load/reload supervisor configs
sudo supervisorctl reread 2>/dev/null || true
sudo supervisorctl update 2>/dev/null || true
sudo supervisorctl start nginx-proxy-manager 2>/dev/null || true
sudo supervisorctl start npm-nginx 2>/dev/null || true

# Wait for NPM API (port 81) to become ready
echo "→ Waiting for Nginx Proxy Manager (port 81)..."
READY=false
for i in $(seq 1 60); do
    if curl -sf http://localhost:81/api/ > /dev/null 2>&1; then
        READY=true
        echo "→ NPM is ready"
        break
    fi
    sleep 2
done

if [ "$READY" = "false" ]; then
    echo "→ Warning: NPM did not start in time, skipping auto-configuration"
    exec "$@"
fi

# Skip if already configured
CONFIGURED_FLAG="/data/.npm-configured"
if [ -f "$CONFIGURED_FLAG" ]; then
    exec "$@"
fi

# Load services config
source /etc/devdesk-npm.env
echo "→ Configuring Nginx Proxy Manager..."

# --- Get initial auth token (NPM default credentials) ---
TOKEN_RESPONSE=$(curl -sf -X POST http://localhost:81/api/tokens \
    -H "Content-Type: application/json" \
    -d '{"identity":"admin@example.com","secret":"changeme"}' 2>/dev/null || echo "")

TOKEN=$(echo "$TOKEN_RESPONSE" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
    echo "→ Warning: Could not get NPM auth token, skipping auto-configuration"
    exec "$@"
fi

# --- Update admin credentials if changed from defaults ---
if [ "$NPM_ADMIN_EMAIL" != "admin@example.com" ] || [ "$NPM_ADMIN_PASSWORD" != "changeme" ]; then
    curl -sf -X PUT http://localhost:81/api/users/1 \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"${NPM_ADMIN_EMAIL}\",\"name\":\"Admin\"}" > /dev/null 2>&1 || true

    curl -sf -X PUT http://localhost:81/api/users/1/auth \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"type\":\"password\",\"current\":\"changeme\",\"secret\":\"${NPM_ADMIN_PASSWORD}\"}" > /dev/null 2>&1 || true

    echo "→ Admin credentials updated"
fi

# --- Generate self-signed wildcard certificate for *.localhost ---
echo "→ Generating self-signed certificate for *.localhost..."

cat > /tmp/npm-openssl.cnf << 'OPENSSLEOF'
[req]
prompt = no
distinguished_name = dn
x509_extensions = v3_req

[dn]
CN = localhost

[v3_req]
subjectAltName = DNS:localhost, DNS:*.localhost
OPENSSLEOF

openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/npm-localhost-key.pem \
    -out /tmp/npm-localhost-cert.pem \
    -days 3650 -nodes \
    -config /tmp/npm-openssl.cnf 2>/dev/null

rm -f /tmp/npm-openssl.cnf

# --- Upload certificate to NPM ---
CERT_RESPONSE=$(curl -sf -X POST http://localhost:81/api/nginx/certificates \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"provider":"other","nice_name":"localhost wildcard (self-signed)"}' 2>/dev/null || echo "")

CERT_ID=$(echo "$CERT_RESPONSE" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('id',0))" 2>/dev/null || echo "0")

if [ "$CERT_ID" != "0" ] && [ -n "$CERT_ID" ]; then
    curl -sf -X POST "http://localhost:81/api/nginx/certificates/${CERT_ID}/upload" \
        -H "Authorization: Bearer $TOKEN" \
        -F "certificate=@/tmp/npm-localhost-cert.pem" \
        -F "certificate_key=@/tmp/npm-localhost-key.pem" > /dev/null 2>&1 || true
    echo "→ Certificate created (ID: $CERT_ID)"
else
    CERT_ID=0
    echo "→ Warning: Could not create certificate, proxy hosts will use HTTP only"
fi

rm -f /tmp/npm-localhost-cert.pem /tmp/npm-localhost-key.pem

# --- Determine SSL settings ---
SSL_FORCED=false
[ "$NPM_HTTPS_ONLY" = "true" ] && SSL_FORCED=true

# --- Create proxy hosts for each service ---
echo "→ Creating proxy hosts..."
IFS=',' read -ra SERVICE_ARRAY <<< "$NPM_SERVICES"
for service in "${SERVICE_ARRAY[@]}"; do
    IFS=':' read -r name port desc icon <<< "$service"
    subdomain=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/-/g')
    domain="${subdomain}.localhost"

    RESULT=$(curl -sf -X POST http://localhost:81/api/proxy-hosts \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"${domain}\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"127.0.0.1\",
            \"forward_port\": ${port},
            \"access_list_id\": 0,
            \"certificate_id\": ${CERT_ID},
            \"ssl_forced\": ${SSL_FORCED},
            \"block_exploits\": false,
            \"allow_websocket_upgrade\": true,
            \"http2_support\": false,
            \"hsts_enabled\": false,
            \"hsts_subdomains\": false,
            \"advanced_config\": \"\"
        }" 2>/dev/null || echo "")

    if echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if d.get('id') else 1)" 2>/dev/null; then
        echo "  → https://${domain} → localhost:${port}"
    else
        echo "  → Warning: Failed to create proxy host for ${domain}"
    fi
done

# Mark as configured
touch "$CONFIGURED_FLAG"
echo "→ Done! Nginx Proxy Manager configured successfully."
echo "→ Admin UI: http://localhost:81  (${NPM_ADMIN_EMAIL} / ${NPM_ADMIN_PASSWORD})"

exec "$@"
ENTRYPOINTEOF

chmod +x /usr/local/bin/devdesk-npm-entrypoint

echo "Nginx Proxy Manager installation complete!"
