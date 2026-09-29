#!/usr/bin/env bash
# deploy.sh — ship deploy/clients/caddy/Caddyfile to corecuity-clients. Run from the Mac, from anywhere.
#
#   core/elmaati/deploy/clients/caddy/deploy.sh           # validate, back up, install, reload
#   core/elmaati/deploy/clients/caddy/deploy.sh --check   # validate on the host only; changes nothing
#
# The Caddyfile imports auth.caddy, which lives ONLY on the server (bcrypt hashes). On the first deploy the
# file prepared by split-auth.py (/etc/caddy/auth.caddy.new) becomes /etc/caddy/auth.caddy.
# Roll back: sudo cp /etc/caddy/Caddyfile.bak-<ts> /etc/caddy/Caddyfile && sudo systemctl reload caddy
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-deploy}"
HOST="${HOST:-corecuity-clients}"

read -r -d '' REMOTE <<'REMOTE' || true
set -euo pipefail
d=$(sudo mktemp -d); trap 'sudo rm -rf "$d"' EXIT
sudo tar -C "$d" -xzf /dev/stdin
AUTH=/etc/caddy/auth.caddy; sudo test -f "$AUTH" || AUTH=/etc/caddy/auth.caddy.new
sudo test -f "$AUTH" || { echo "✗ no auth.caddy on the server — run split-auth.py first"; exit 1; }
sudo cp "$AUTH" "$d/auth.caddy"
out=$(sudo caddy validate --adapter caddyfile --config "$d/Caddyfile" 2>&1) || { echo "✗ Caddyfile invalid:"; echo "$out" | tail -5; exit 1; }
echo "✓ valid on $(hostname) ($(sudo grep -cE '^[a-z0-9][^ ]*.*\{\s*$' "$d/Caddyfile") site blocks)"
[ "$MODE" = "--check" ] && { echo "(check only — nothing changed)"; exit 0; }
ts=$(date +%Y%m%d-%H%M%S)
sudo cp -p /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak-$ts
sudo test -f /etc/caddy/auth.caddy || sudo mv /etc/caddy/auth.caddy.new /etc/caddy/auth.caddy
sudo chown root:caddy /etc/caddy/auth.caddy; sudo chmod 0640 /etc/caddy/auth.caddy
sudo install -o root -g caddy -m0640 "$d/Caddyfile" /etc/caddy/Caddyfile
sudo systemctl reload caddy
echo "✓ deployed (backup: /etc/caddy/Caddyfile.bak-$ts)"; systemctl is-active caddy
REMOTE

# stdin carries the Caddyfile tarball, so the remote script travels as a base64 argument.
COPYFILE_DISABLE=1 tar -C "$HERE" -czf - Caddyfile \
  | ssh "$HOST" "MODE=$MODE bash -c \"\$(echo $(printf '%s' "$REMOTE" | base64 | tr -d '\n') | base64 -d)\"" 2>&1 | grep -v LIBARCHIVE
