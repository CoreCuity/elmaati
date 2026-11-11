#!/usr/bin/env bash
# Run from the pulled checkout on corecuity-HQ.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
sudo caddy validate --adapter caddyfile --config "$HERE/Caddyfile"
sudo install -d -o root -g root -m0755 /var/www/fleet-floor
if sudo test -f /var/www/fleet-floor/index.html; then
    sudo cp -p /var/www/fleet-floor/index.html "/var/www/fleet-floor/index.html.bak-$(date +%Y%m%d-%H%M%S)"
fi
sudo install -o root -g root -m0644 "$HERE/fleet-floor/index.html" /var/www/fleet-floor/index.html
bash "$HERE/install-config.sh"
