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

echo "→ Uploading the dashboard to $HOST …"
tar -C web/admin -czf - . | ssh "$HOST" 'rm -rf /tmp/hisab-admin && mkdir -p /tmp/hisab-admin && tar -xzf - -C /tmp/hisab-admin'

echo "→ Setting up nginx for https://$DOMAIN/hisab/dashboard/ …"
ssh "$HOST" "DOMAIN='$DOMAIN' EMAIL='$EMAIL' bash -s" <<'REMOTE'
set -euo pipefail
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
WEB=/var/www/hisab-admin
SNIP=/etc/nginx/snippets/hisab-admin.conf
STAMP=$(date +%Y%m%d%H%M%S)

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
$SUDO chown -R www-data:www-data "$WEB" 2>/dev/null || true
$SUDO find "$WEB" -type d -exec chmod 755 {} \; ; $SUDO find "$WEB" -type f -exec chmod 644 {} \;

# the location block, shared by both cases
$SUDO mkdir -p /etc/nginx/snippets
$SUDO tee "$SNIP" >/dev/null <<NGINX
# Hisab AI web admin — managed by tool/deploy_admin.sh
location = /hisab { return 301 /hisab/dashboard/; }
location = /hisab/ { return 301 /hisab/dashboard/; }
location = /hisab/dashboard { return 301 /hisab/dashboard/; }
# the old address keeps working
location = /gamex { return 301 /hisab/dashboard/; }
location ^~ /gamex/ { return 301 /hisab/dashboard/; }
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
EXISTING=$(grep -RlE "server_name[^;]*[[:space:]]$DOMAIN([[:space:];]|\$)" /etc/nginx/sites-enabled /etc/nginx/conf.d 2>/dev/null | sort -u || true)
NEW_SITE=0
if [ -n "$EXISTING" ]; then
  for F in $EXISTING; do
    REAL=$(readlink -f "$F")
    if ! grep -q "snippets/hisab-admin.conf" "$REAL"; then
      echo "  adding /hisab/dashboard to $REAL (backup: $REAL.bak-$STAMP)"
      $SUDO cp "$REAL" "$REAL.bak-$STAMP"
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
  for F in $EXISTING; do REAL=$(readlink -f "$F"); [ -f "$REAL.bak-$STAMP" ] && $SUDO cp "$REAL.bak-$STAMP" "$REAL"; done
  [ "$NEW_SITE" = 1 ] && $SUDO rm -f /etc/nginx/sites-enabled/hisab-admin /etc/nginx/sites-available/hisab-admin /etc/nginx/conf.d/hisab-admin.conf
  exit 1
fi
$SUDO systemctl reload nginx || $SUDO nginx -s reload

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
REMOTE
