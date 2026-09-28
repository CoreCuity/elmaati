#!/usr/bin/env bash
# install-fleet-status.sh — install the fleet's read-only probe on a host. Run as root; idempotent.
#
# Run from the Mac (source of truth = this folder; never edit on a server):
#   COPYFILE_DISABLE=1 tar -C core/elmaati/deploy/provision -czf - fleet-status fleet-tenant-backups \
#       fleet-backup-sources fleetwatch.authorized_keys hosts install-fleet-status.sh \
#     | ssh <host> 'd=$(mktemp -d) && tar -C $d -xzf - && sudo bash $d/install-fleet-status.sh [<hosts/NAME>] && rm -rf $d'
#
#   0. fleetwatch system user (if missing) + its key, forced to run fleet-status only
#   1. fleet-status          → /usr/local/bin  (the fleetwatch key's forced command)
#   2. fleet-tenant-backups  → /usr/local/sbin (root helper: tenant systemd-user backup facts, no input)
#      fleet-backup-sources  → /usr/local/sbin (root helper: cron-log / JetBackup facts, no input)
#   3. [optional NAME] hosts/NAME.json → /etc/fleet-status/backup-sources.json (root-owned list of sources)
#   4. one sudo rule per helper: fleetwatch may run it as root with NO arguments, nothing else
#   5. prove it: run fleet-status as fleetwatch, and show fleetwatch's full sudo rights
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
HOSTCONF="${1:-}"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }

# 0. fleetwatch — a login shell is required for the forced command to run; safety comes from restrict+command=
if ! id fleetwatch >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /var/lib/fleetwatch --shell /bin/sh \
          --comment "CoreCuity fleet read-only watcher" fleetwatch
  echo "+ fleetwatch user created"
fi
install -d -o fleetwatch -g fleetwatch -m0700 /var/lib/fleetwatch/.ssh
install -o root -g fleetwatch -m0640 "${SRC}/fleetwatch.authorized_keys" /var/lib/fleetwatch/.ssh/authorized_keys

install -o root -g root -m0755 "${SRC}/fleet-status" /usr/local/bin/fleet-status
install -o root -g root -m0755 "${SRC}/fleet-tenant-backups" /usr/local/sbin/fleet-tenant-backups
install -o root -g root -m0755 "${SRC}/fleet-backup-sources" /usr/local/sbin/fleet-backup-sources
if [ -n "$HOSTCONF" ]; then
  install -d -o root -g root -m0755 /etc/fleet-status
  install -o root -g root -m0644 "${SRC}/hosts/${HOSTCONF}.json" /etc/fleet-status/backup-sources.json
  echo "+ backup sources: hosts/${HOSTCONF}.json"
fi

RULE=/etc/sudoers.d/fleetwatch-tenant-backups
TMP="$(mktemp)"
cat > "$TMP" <<'EOF'
# Managed by core/elmaati/deploy/provision/install-fleet-status.sh — fleet read-only watch.
# fleetwatch may run the backup-facts helpers as root with NO arguments ("" = none allowed).
fleetwatch ALL=(root) NOPASSWD: /usr/local/sbin/fleet-tenant-backups ""
fleetwatch ALL=(root) NOPASSWD: /usr/local/sbin/fleet-backup-sources ""
EOF
visudo -cf "$TMP" >/dev/null
install -o root -g root -m0440 "$TMP" "$RULE"
rm -f "$TMP"
visudo -cf "$RULE" >/dev/null   # only our file: other sudoers files (e.g. cPanel's) are not ours to judge

echo "── fleetwatch sudo rights (must list only the helper):"
sudo -u fleetwatch sudo -n -l 2>&1 | sed -n '/may run/,$p'
echo "── tenant_backups as seen through fleet-status:"
sudo -u fleetwatch /usr/local/bin/fleet-status | python3 -c '
import json, sys
d = json.load(sys.stdin); t = d.get("tenant_backups") or {}
units, users = t.get("units", []), t.get("lingering_users", [])
print("schema", d["schema"], "|", t.get("error") or "%d tenant units across %d users" % (len(units), len(users)))
for u in units: print("  ", u["user"], u["unit"], u["result"])
for b in d.get("backup_sources") or []: print("   source", b.get("name"), "| last success", b.get("last_success"), b.get("error", ""))'
