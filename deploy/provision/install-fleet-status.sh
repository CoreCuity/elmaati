#!/usr/bin/env bash
# install-fleet-status.sh — install the fleet's read-only probe on a host. Run as root; idempotent.
#
# Run from the Mac (source of truth = this folder; never edit on a server):
#   tar -C core/elmaati/deploy/provision -czf - fleet-status fleet-tenant-backups install-fleet-status.sh \
#     | ssh <host> 'd=$(mktemp -d) && tar -C $d -xzf - && sudo bash $d/install-fleet-status.sh && rm -rf $d'
#
#   1. fleet-status          → /usr/local/bin  (the fleetwatch key's forced command)
#   2. fleet-tenant-backups  → /usr/local/sbin (root helper: tenant backup facts, no input)
#   3. one sudo rule: fleetwatch may run that helper as root, with NO arguments, nothing else
#   4. prove it: run fleet-status as fleetwatch, and show fleetwatch's full sudo rights
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
id fleetwatch >/dev/null 2>&1 || { echo "✗ no fleetwatch user on this host" >&2; exit 1; }

install -o root -g root -m0755 "${SRC}/fleet-status" /usr/local/bin/fleet-status
install -o root -g root -m0755 "${SRC}/fleet-tenant-backups" /usr/local/sbin/fleet-tenant-backups

RULE=/etc/sudoers.d/fleetwatch-tenant-backups
TMP="$(mktemp)"
cat > "$TMP" <<'EOF'
# Managed by core/elmaati/deploy/provision/install-fleet-status.sh — fleet read-only watch.
# fleetwatch may run the tenant-backup facts helper as root with NO arguments ("" = none allowed).
fleetwatch ALL=(root) NOPASSWD: /usr/local/sbin/fleet-tenant-backups ""
EOF
visudo -cf "$TMP" >/dev/null
install -o root -g root -m0440 "$TMP" "$RULE"
rm -f "$TMP"
visudo -c >/dev/null

echo "── fleetwatch sudo rights (must list only the helper):"
sudo -u fleetwatch sudo -n -l 2>&1 | sed -n '/may run/,$p'
echo "── tenant_backups as seen through fleet-status:"
sudo -u fleetwatch /usr/local/bin/fleet-status | python3 -c '
import json, sys
d = json.load(sys.stdin); t = d.get("tenant_backups") or {}
units, users = t.get("units", []), t.get("lingering_users", [])
print("schema", d["schema"], "|", t.get("error") or "%d tenant units across %d users" % (len(units), len(users)))
for u in units: print("  ", u["user"], u["unit"], u["result"])'
