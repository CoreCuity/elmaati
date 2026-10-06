#!/usr/bin/env bash
# Run from the pulled elmaati checkout on corecuity-HQ.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
sudo caddy validate --adapter caddyfile --config "$HERE/Caddyfile"
STAMP="$(date +%Y%m%d-%H%M%S)"
sudo cp -p /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak-$STAMP"
sudo install -o root -g root -m0644 "$HERE/Caddyfile" /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo systemctl is-active caddy
