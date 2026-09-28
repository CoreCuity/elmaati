#!/usr/bin/env bash
# deploy.sh — ship deploy/hq/caddy/ to corecuity-HQ. Run from the Mac, from anywhere.
#
#   core/elmaati/deploy/hq/caddy/deploy.sh
#
# 1. validate the Caddyfile on the host (with the host's own caddy binary) before touching anything
# 2. back up the live /etc/caddy/Caddyfile to /etc/caddy/Caddyfile.bak-<timestamp>
# 3. install the Caddyfile + the static site (www/ → /var/www/corecuity), then a graceful reload
# 4. show the result; roll back with: sudo cp /etc/caddy/Caddyfile.bak-<ts> /etc/caddy/Caddyfile && sudo systemctl reload caddy
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HOST="${1:-corecuity-HQ}"

COPYFILE_DISABLE=1 tar -C "$HERE" -czf - Caddyfile www | ssh "$HOST" 'set -euo pipefail
d=$(mktemp -d); trap "rm -rf $d" EXIT
tar -C $d -xzf - 2>/dev/null
caddy validate --adapter caddyfile --config $d/Caddyfile >/dev/null 2>$d/err || { echo "✗ Caddyfile invalid:"; cat $d/err; exit 1; }
ts=$(date +%Y%m%d-%H%M%S)
sudo cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-$ts
sudo install -o root -g root -m0644 $d/Caddyfile /etc/caddy/Caddyfile
sudo install -d -o root -g root -m0755 /var/www/corecuity
sudo cp -r $d/www/. /var/www/corecuity/
sudo chown -R root:root /var/www/corecuity; sudo find /var/www/corecuity -type d -exec chmod 755 {} +; sudo find /var/www/corecuity -type f -exec chmod 644 {} +
sudo systemctl reload caddy
echo "✓ deployed (backup: /etc/caddy/Caddyfile.bak-$ts)"; systemctl is-active caddy'
