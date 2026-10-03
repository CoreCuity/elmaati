#!/usr/bin/env bash
# install.sh — fleet-meta, the fleet's read-only view of Meta ads, on corecuity-HQ. Run as root; idempotent.
#
# Run from the Mac (source of truth = this repo; never edit on the server):
#   COPYFILE_DISABLE=1 tar -C core/elmaati/deploy/hq -czf - fleet-meta \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-meta && sudo tar -C /root -xzf - \
#         && sudo bash /root/fleet-meta/install.sh && sudo rm -rf /root/fleet-meta'
# The token (CoreCuity's Meta user token, fleet-v1 §6.3 exception) — first install and after every
# rotation (swap-meta-token.sh), from the Mac:
#   (. .secrets/meta-ads.env && printf %s "$META_ACCESS_TOKEN") \
#     | ssh corecuity-HQ 'sudo install -o root -g fleetmeta -m0640 /dev/stdin /etc/fleet-meta/token'
# then run install.sh again so its checks reach Meta.
#
#   1. system user fleetmeta (no shell, no home): the only holder of the token on the box
#   2. /etc/fleet-meta/token root:fleetmeta 0640 — svc-hermes cannot read it
#   3. /usr/local/libexec/fleet-meta-read (GET only, Adolia only) + /usr/local/bin/fleet-meta (the door)
#   4. sudoers: svc-hermes may run that one binary as fleetmeta — nothing else, as nobody else
#   5. checks
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
U=svc-hermes
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
say() { echo "── $* ──"; }
fail() { echo "✗ $*" >&2; exit 1; }

say "1/5 user fleetmeta"
id fleetmeta >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin fleetmeta
echo "   $(id fleetmeta)"

say "2/5 /etc/fleet-meta"
install -d -o root -g fleetmeta -m0750 /etc/fleet-meta
if [ -f /etc/fleet-meta/token ]; then
  chown root:fleetmeta /etc/fleet-meta/token && chmod 0640 /etc/fleet-meta/token
  echo "   token present"
else
  echo "   no token yet — push it from the Mac (see header), then re-run"
fi

say "3/5 tools (root-owned)"
install -d -o root -g root -m0755 /usr/local/libexec
install -o root -g root -m0755 "${SRC}/fleet-meta-read" /usr/local/libexec/fleet-meta-read
install -o root -g root -m0755 "${SRC}/fleet-meta" /usr/local/bin/fleet-meta

say "4/5 sudoers"
SUD=/etc/sudoers.d/fleet-meta
TMP="$(mktemp)"
cat > "$TMP" <<EOF
# Managed by core/elmaati/deploy/hq/fleet-meta/install.sh
# svc-hermes may run ONE read-only binary as fleetmeta (the Meta token holder). Nothing else.
Defaults:${U} !use_pty
${U} ALL=(fleetmeta) NOPASSWD: /usr/local/libexec/fleet-meta-read
${U} ALL=(fleetmeta) NOPASSWD: /usr/local/libexec/fleet-meta-read *
EOF
visudo -cqf "$TMP" || fail "sudoers rule does not validate"
install -o root -g root -m0440 "$TMP" "$SUD"; rm -f "$TMP"
echo "   $(sudo -l -U "$U" | grep -c fleet-meta-read) rule(s) for ${U}"

say "5/5 checks"
as() { sudo -u "$U" -H "$@"; }
as test -r /etc/fleet-meta/token && fail "svc-hermes can read the token"
echo "   svc-hermes cannot read the token"
as sudo -n -u fleetmeta /bin/cat /etc/fleet-meta/token >/dev/null 2>&1 && fail "svc-hermes can run other commands as fleetmeta"
as sudo -n -u root /usr/local/libexec/fleet-meta-read account adolia >/dev/null 2>&1 && fail "svc-hermes can run the tool as root"
echo "   no other sudo: cat as fleetmeta refused, root refused"
grep -qE "method=|Request\([^)]*method|data=" /usr/local/libexec/fleet-meta-read && fail "the tool can send something other than a GET"
r="$(as /usr/local/bin/fleet-meta account odae || true)"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["exit_code"]==4, r; print("   ad account outside the list refused")'
r="$(as /usr/local/bin/fleet-meta results adolia --since=2026-01-01 --until=2026-12-31 || true)"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["exit_code"]==4, r; print("   oversized date range refused")'
if [ -f /etc/fleet-meta/token ]; then
  r="$(as /usr/local/bin/fleet-meta account adolia)"
  echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"], r; print("   adolia:", r["name"], "·", r["status"], "·", r["timezone"])'
fi
echo "   done. Calls are logged: journalctl -t fleet-meta"
