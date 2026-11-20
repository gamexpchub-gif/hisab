#!/usr/bin/env bash
# =============================================================================
# Deploys the Hisab AI web admin (web/admin) to your VPS at
#   https://<domain>/hisab/dashboard/
#
# Run it on YOUR computer (where this repo is), not on the VPS:
#   bash tool/deploy_admin.sh root@200.234.32.137 admin.deencircle.online you@email.com
#
# It uses your own SSH login (key or password prompt). On the VPS it:
#   - installs nginx and certbot if they are missing (Debian / Ubuntu)
#   - copies the dashboard to /var/www/hisab-admin/hisab/dashboard
#   - adds a /hisab/dashboard location to the site of <domain> if nginx already
#     serves it (the existing site keeps working), or creates a new site
#   - gets a free HTTPS certificate (Let's Encrypt) when the site has none
# Safe to run again for updates: only the dashboard files are replaced.
# =============================================================================
set -euo pipefail

HOST="${1:-}"
DOMAIN="${2:-admin.deencircle.online}"
EMAIL="${3:-}"
if [ -z "$HOST" ]; then
  echo "Usage: bash tool/deploy_admin.sh root@<vps-ip> [domain] [email-for-ssl]"
  exit 1
fi
cd "$(dirname "$0")/.."
[ -f web/admin/index.html ] || { echo "web/admin/index.html not found — run git pull first"; exit 1; }

echo "→ Uploading the dashboard and the invoice page to $HOST …"
tar -C web/admin -czf - . | ssh "$HOST" 'rm -rf /tmp/hisab-admin && mkdir -p /tmp/hisab-admin && tar -xzf - -C /tmp/hisab-admin'
tar -C web/invoice -czf - . | ssh "$HOST" 'rm -rf /tmp/hisab-invoice && mkdir -p /tmp/hisab-invoice && tar -xzf - -C /tmp/hisab-invoice'
ssh "$HOST" 'cat > /tmp/hisab_sync.py' < tool/vps/hisab_sync.py

echo "→ Setting up nginx for https://$DOMAIN/hisab/dashboard/ …"
ssh "$HOST" "DOMAIN='$DOMAIN' EMAIL='$EMAIL' bash -s" <<'REMOTE'
set -euo pipefail
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
WEB=/var/www/hisab-admin
SNIP=/etc/nginx/snippets/hisab-admin.conf
STAMP=$(date +%Y%m%d%H%M%S)
# backups live OUTSIDE /etc/nginx: nginx reads every file in sites-enabled,
# so a copy left there would load the same site twice and break nginx
BK=/root/hisab-nginx-backups/$STAMP
$SUDO mkdir -p "$BK"
bk() { echo "$BK/$(echo "$1" | tr '/' '_')"; }

if ! command -v nginx >/dev/null 2>&1; then
  echo "  installing nginx…"
  $SUDO apt-get update -qq && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nginx >/dev/null
fi
if ! command -v certbot >/dev/null 2>&1; then
  echo "  installing certbot…"
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot python3-certbot-nginx >/dev/null || echo "  (certbot install failed — HTTPS step will be skipped)"
fi

# files
$SUDO mkdir -p "$WEB/hisab/dashboard"
$SUDO rm -rf "$WEB/hisab/dashboard.new"
$SUDO cp -r /tmp/hisab-admin "$WEB/hisab/dashboard.new"
$SUDO rm -rf "$WEB/hisab/dashboard.old"
$SUDO mv "$WEB/hisab/dashboard" "$WEB/hisab/dashboard.old"
$SUDO mv "$WEB/hisab/dashboard.new" "$WEB/hisab/dashboard"
$SUDO rm -rf "$WEB/hisab/dashboard.old" /tmp/hisab-admin "$WEB/gamex"
# customer invoice page (links shared from the app)
$SUDO rm -rf "$WEB/hisab/invoice"
$SUDO cp -r /tmp/hisab-invoice "$WEB/hisab/invoice"
$SUDO rm -rf /tmp/hisab-invoice
$SUDO chown -R www-data:www-data "$WEB" 2>/dev/null || true
$SUDO find "$WEB" -type d -exec chmod 755 {} \; ; $SUDO find "$WEB" -type f -exec chmod 644 {} \;

# phone model database mirror for the app's Smart IMEI (Osmocom TAC database,
# refreshed weekly) — served at /hisab/tacdb/tacdb.csv
$SUDO mkdir -p "$WEB/hisab/tacdb"
$SUDO tee /usr/local/bin/hisab-tacdb-refresh >/dev/null <<'SH'
#!/bin/sh
# Hisab AI — refreshes the TAC (IMEI model) database mirror. Managed by deploy_admin.sh
OUT=/var/www/hisab-admin/hisab/tacdb
TMP=$(mktemp)
for U in https://tacdb.osmocom.org/export/tacdb.csv http://tacdb.osmocom.org/export/tacdb.csv; do
  if curl -fsSL -m 300 -A "HisabAI-mirror/1.0" -o "$TMP" "$U" && [ "$(wc -l < "$TMP")" -gt 1000 ] && head -1 "$TMP" | grep -qi tac; then
    install -m 644 "$TMP" "$OUT/tacdb.csv.new" && mv -f "$OUT/tacdb.csv.new" "$OUT/tacdb.csv"
    rm -f "$TMP"; echo "tacdb: $(wc -l < "$OUT/tacdb.csv") lines from $U"; exit 0
  fi
done
rm -f "$TMP"; echo "tacdb: download failed (old copy kept)" >&2; exit 1
SH
$SUDO chmod 755 /usr/local/bin/hisab-tacdb-refresh
$SUDO ln -sf /usr/local/bin/hisab-tacdb-refresh /etc/cron.weekly/hisab-tacdb-refresh
echo "  downloading the phone model database…"
$SUDO /usr/local/bin/hisab-tacdb-refresh || echo "  ⚠ phone model database download failed — the app falls back to Osmocom directly"

# live sync server: the app sends every change of the books here within
# seconds (photos stay in Firebase). Python standard library only.
if ! command -v python3 >/dev/null 2>&1; then
  echo "  installing python3…"
  $SUDO apt-get update -qq && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 >/dev/null
fi
id hisab-sync >/dev/null 2>&1 || $SUDO useradd --system --no-create-home --shell /usr/sbin/nologin hisab-sync
$SUDO mkdir -p /opt/hisab-sync /var/lib/hisab-sync
$SUDO install -m 755 /tmp/hisab_sync.py /opt/hisab-sync/hisab_sync.py && rm -f /tmp/hisab_sync.py
$SUDO chown -R hisab-sync:hisab-sync /var/lib/hisab-sync
$SUDO chmod 700 /var/lib/hisab-sync
$SUDO tee /etc/systemd/system/hisab-sync.service >/dev/null <<'UNIT'
[Unit]
Description=Hisab AI live sync server
After=network-online.target
Wants=network-online.target

[Service]
User=hisab-sync
Group=hisab-sync
Environment=HISAB_DATA=/var/lib/hisab-sync
Environment=HISAB_PORT=8787
ExecStart=/usr/bin/env python3 /opt/hisab-sync/hisab_sync.py
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/var/lib/hisab-sync

[Install]
WantedBy=multi-user.target
UNIT
$SUDO systemctl daemon-reload
$SUDO systemctl enable hisab-sync >/dev/null 2>&1 || true
$SUDO systemctl restart hisab-sync
sleep 1
if curl -fsS -m 5 http://127.0.0.1:8787/health >/dev/null 2>&1; then
  echo "  live sync server running (127.0.0.1:8787)"
else
  echo "  ⚠ live sync server did not start — see: journalctl -u hisab-sync -n 50"
fi

# the location block, shared by both cases (the old one is kept until the
# new config passes "nginx -t", so a clash never takes the other sites down)
$SUDO mkdir -p /etc/nginx/snippets
SNIP_OLD=""
if [ -f "$SNIP" ]; then SNIP_OLD="$(bk "$SNIP")"; $SUDO cp "$SNIP" "$SNIP_OLD"; fi
$SUDO tee "$SNIP" >/dev/null <<NGINX
# Hisab AI web admin — managed by tool/deploy_admin.sh
location = /hisab { return 301 /hisab/dashboard/; }
location = /hisab/ { return 301 /hisab/dashboard/; }
location = /hisab/dashboard { return 301 /hisab/dashboard/; }
location = /hisab/invoice { return 301 /hisab/invoice/; }
location ^~ /hisab/invoice/ {
    root $WEB;
    index index.html;
    try_files \$uri \$uri/ /hisab/invoice/index.html;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "DENY" always;
    add_header Content-Security-Policy "default-src 'none'; script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; connect-src https://firestore.googleapis.com; style-src 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" always;
    add_header Cache-Control "no-cache";
}
location ^~ /hisab/api/ {
    proxy_pass http://127.0.0.1:8787;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 60s;
    proxy_request_buffering on;
    client_max_body_size 10m;
    add_header Cache-Control "no-store" always;
    add_header X-Content-Type-Options "nosniff" always;
}
location ^~ /hisab/tacdb/ {
    root $WEB;
    default_type text/csv;
    gzip on;
    gzip_types text/csv text/plain;
    add_header Cache-Control "public, max-age=86400";
    add_header X-Content-Type-Options "nosniff" always;
}
location ^~ /hisab/dashboard/ {
    root $WEB;
    index index.html;
    try_files \$uri \$uri/ /hisab/dashboard/index.html;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    location ~* \.html\$ { add_header Cache-Control "no-cache"; add_header X-Frame-Options "DENY" always; add_header X-Robots-Tag "noindex, nofollow" always; }
}
NGINX

# is the domain already served by nginx?
# copies an older version of this script left inside nginx's folders
for F in /etc/nginx/sites-enabled/*.bak-[0-9]* /etc/nginx/conf.d/*.bak-[0-9]*; do
  if [ -f "$F" ]; then $SUDO mv "$F" "$BK/"; echo "  moved an old backup out of nginx: $F"; fi
done
EXISTING=$(grep -RlE --exclude='*.bak*' "server_name[^;]*[[:space:]]$DOMAIN([[:space:];]|\$)" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | sort -u || true)
NEW_SITE=0
if [ -n "$EXISTING" ]; then
  for F in $EXISTING; do
    REAL=$(readlink -f "$F")
    if ! grep -q "snippets/hisab-admin.conf" "$REAL"; then
      echo "  adding /hisab/dashboard to $REAL (backup: $(bk "$REAL"))"
      $SUDO cp "$REAL" "$(bk "$REAL")"
      $SUDO sed -i -E "/server_name[^;]*[[:space:]]${DOMAIN//./\\.}([[:space:];]|\$)/a\\    include snippets/hisab-admin.conf;" "$REAL"
    else
      echo "  $REAL already includes the dashboard"
    fi
  done
else
  NEW_SITE=1
  if [ -d /etc/nginx/sites-available ]; then CONF=/etc/nginx/sites-available/hisab-admin; else CONF=/etc/nginx/conf.d/hisab-admin.conf; fi
  echo "  creating a new site for $DOMAIN ($CONF)"
  $SUDO tee "$CONF" >/dev/null <<NGINX
server {
    listen 80;
$( [ -f /proc/net/if_inet6 ] && echo '    listen [::]:80;' )
    server_name $DOMAIN;
    root $WEB;
    location = / { return 302 /hisab/dashboard/; }
    include snippets/hisab-admin.conf;
}
NGINX
  [ -d /etc/nginx/sites-enabled ] && $SUDO ln -sf "$CONF" /etc/nginx/sites-enabled/hisab-admin
fi

if ! $SUDO nginx -t 2>/tmp/nginx-test.log; then
  echo "  ✗ nginx config test failed — undoing changes:"
  cat /tmp/nginx-test.log
  for F in $EXISTING; do REAL=$(readlink -f "$F"); [ -f "$(bk "$REAL")" ] && $SUDO cp "$(bk "$REAL")" "$REAL"; done
  [ "$NEW_SITE" = 1 ] && $SUDO rm -f /etc/nginx/sites-enabled/hisab-admin /etc/nginx/sites-available/hisab-admin /etc/nginx/conf.d/hisab-admin.conf
  if [ -n "$SNIP_OLD" ]; then $SUDO cp "$SNIP_OLD" "$SNIP"; else $SUDO rm -f "$SNIP"; fi
  if $SUDO nginx -t >/dev/null 2>&1; then
    echo "  your other websites are untouched (old config restored)"
  else
    echo "  ⚠ nginx config still fails — check: nginx -t"
  fi
  exit 1
fi
$SUDO systemctl enable nginx >/dev/null 2>&1 || true
$SUDO systemctl reload nginx || $SUDO systemctl restart nginx || $SUDO nginx -s reload

# firewall
if command -v ufw >/dev/null 2>&1 && $SUDO ufw status | grep -q "Status: active"; then
  $SUDO ufw allow 'Nginx Full' >/dev/null || true
fi

# DNS check
MYIP=$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
DNSIP=$(getent ahostsv4 "$DOMAIN" | awk '{print $1; exit}' || true)
if [ -z "$DNSIP" ]; then
  echo "  ⚠ $DOMAIN does not resolve yet — add an A record: $DOMAIN → $MYIP"
elif [ "$DNSIP" != "$MYIP" ]; then
  echo "  ⚠ $DOMAIN points to $DNSIP, but this server is $MYIP — HTTPS may fail until DNS is fixed"
fi

# HTTPS
HAS_TLS=0
for F in $EXISTING; do grep -qE "listen[^;]*443" "$(readlink -f "$F")" && HAS_TLS=1; done
if [ "$HAS_TLS" = 1 ]; then
  echo "  HTTPS already set up for $DOMAIN"
elif command -v certbot >/dev/null 2>&1 && [ -n "$DNSIP" ]; then
  echo "  requesting an HTTPS certificate…"
  if [ -n "$EMAIL" ]; then M="-m $EMAIL"; else M="--register-unsafely-without-email"; fi
  $SUDO certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect $M || echo "  ⚠ certbot failed — the dashboard works on http:// until DNS points here; run this script again later"
fi

echo
echo "✓ Hisab AI admin is live:  https://$DOMAIN/hisab/dashboard/"
if curl -fsS -m 8 "https://$DOMAIN/hisab/api/health" >/dev/null 2>&1 || curl -fsS -m 8 "http://$DOMAIN/hisab/api/health" >/dev/null 2>&1; then
  echo "✓ Live sync server is live:  https://$DOMAIN/hisab/api/health"
else
  echo "  ⚠ https://$DOMAIN/hisab/api/health did not answer yet — check DNS / HTTPS"
fi
REMOTE
