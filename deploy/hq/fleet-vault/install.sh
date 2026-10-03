#!/usr/bin/env bash
# install.sh — the fleet's vault on corecuity-HQ (fleet-v1 §5). Run as root; idempotent.
#
# Run from the Mac (source of truth = this repo; never edit on the server):
#   COPYFILE_DISABLE=1 tar -C core/elmaati/deploy/hq -czf - fleet-vault \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-vault && sudo tar -C /root -xzf - \
#         && sudo bash /root/fleet-vault/install.sh && sudo rm -rf /root/fleet-vault'
#
#   1. rules + tools, root-owned: /usr/local/lib/fleet-vault/fleet_vault.py, /usr/local/bin/fleet-note,
#      /usr/local/sbin/fleet-vault-ingest
#   2. the vault: /var/lib/fleet-vault, root:svc-hermes, read-only for the fleet. Client folders, cards
#      and timelines are NOT created here — the founders ship them from the Mac (tools/fleet-vault).
#   3. the inbox (svc-hermes) and the root path unit that ingests it
#   4. checks: the fleet cannot write the vault; a bad note is refused; a good note round-trips
# Add /var/lib/fleet-vault to the hq off-site backup SOURCE (tools/offsite-backup/envs/hq.env) once.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
U=svc-hermes
V=/var/lib/fleet-vault
INBOX="/home/${U}/.local/state/fleet-vault/inbox"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
say() { echo "── $* ──"; }

say "1/4 rules and tools (root-owned)"
install -d -m0755 /usr/local/lib/fleet-vault
install -o root -g root -m0644 "${SRC}/fleet_vault.py" /usr/local/lib/fleet-vault/fleet_vault.py
install -o root -g root -m0755 "${SRC}/fleet-note" /usr/local/bin/fleet-note
install -o root -g root -m0755 "${SRC}/fleet-vault-ingest" /usr/local/sbin/fleet-vault-ingest

say "2/4 vault → ${V} (root:${U}, the fleet reads only)"
for d in "$V" "$V/clients" "$V/fleet" "$V/fleet/journal" "$V/.results"; do install -d -o root -g "$U" -m0750 "$d"; done
install -o root -g "$U" -m0640 "${SRC}/Home.md" "$V/Home.md"

say "3/4 inbox and ingest unit"
sudo -u "$U" -H mkdir -p "$INBOX"
chmod 0700 "$INBOX"
cat > /etc/systemd/system/fleet-vault-ingest.service <<'EOF'
# Managed by core/elmaati/deploy/hq/fleet-vault/install.sh
[Unit]
Description=Fleet vault — check and append the fleet's notes (root; the fleet cannot write the vault)
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/fleet-vault-ingest
NoNewPrivileges=yes
PrivateNetwork=yes
PrivateTmp=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/fleet-vault /home/svc-hermes/.local/state/fleet-vault
EOF
cat > /etc/systemd/system/fleet-vault-ingest.path <<EOF
# Managed by core/elmaati/deploy/hq/fleet-vault/install.sh
[Unit]
Description=Fleet vault — ingest a note as soon as the fleet drops one
[Path]
PathExistsGlob=${INBOX}/*.json
Unit=fleet-vault-ingest.service
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now fleet-vault-ingest.path >/dev/null

say "4/4 checks"
fail() { echo "✗ $*" >&2; exit 1; }
sudo -u "$U" -H test -r "$V/Home.md" || fail "the fleet cannot read the vault"
if sudo -u "$U" -H test -w "$V" || sudo -u "$U" -H test -w "$V/Home.md" || sudo -u "$U" -H test -w "$V/clients"; then
  fail "the fleet can write the vault"
fi
echo "   fleet reads the vault, cannot write it"
note() { sudo -u "$U" -H /usr/local/bin/fleet-note "$@" || true; }
r="$(note --client=no-such-client --kind=event --source=observation --text='This note must be refused: unknown client.')"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["exit_code"]==4, r; print("   unknown client refused")'
r="$(note --client=fleet --kind=lesson --source=observation --text='A lesson with a budget of 1,400 MAD must be refused.')"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["exit_code"]==4 and "money" in r["error"], r; print("   amount of money refused")'
r="$(note --client=fleet --kind=decision --source=observation --text='A decision without a founder as its source must be refused.')"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["exit_code"]==4, r; print("   decision without a founder refused")'
r="$(note --client=fleet --kind=lesson --source=observation --text="Vault installed and checked on $(date +%F): notes are stored through fleet-note only.")"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"], r; print("   good note stored →", r["file"])'
echo "   vault ready. Ship the founder-approved cards from the Mac: python3 tools/fleet-vault/vault.py ship"
