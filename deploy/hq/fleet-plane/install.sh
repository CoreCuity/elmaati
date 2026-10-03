#!/usr/bin/env bash
# install.sh — fleet-plane, the fleet's read-only view of Plane, on corecuity-HQ. Run as root; idempotent.
#
# Run from the Mac (source of truth = this repo; never edit on the server):
#   COPYFILE_DISABLE=1 tar -C core/elmaati/deploy/hq -czf - fleet-plane \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-plane && sudo tar -C /root -xzf - \
#         && sudo bash /root/fleet-plane/install.sh && sudo rm -rf /root/fleet-plane'
# First install only — the token (the fleet's own Plane token, never a founder's), from the Mac:
#   . .secrets/fleet-plane.env && printf %s "$FLEET_PLANE_API_TOKEN" \
#     | ssh corecuity-HQ 'sudo install -o root -g fleetplane -m0640 /dev/stdin /etc/fleet-plane/token'
# then run install.sh again so its checks reach Plane.
#
#   1. system user fleetplane (no shell, no home): the only holder of the token
#   2. /etc/fleet-plane/token root:fleetplane 0640 — svc-hermes cannot read it
#   3. /usr/local/libexec/fleet-plane-read (GET only, 6 projects) + /usr/local/bin/fleet-plane (the door)
#   4. sudoers: svc-hermes may run that one binary as fleetplane — nothing else, as nobody else
#   5. checks
# Which projects Plane lets the fleet see is set in Plane (memberships, Najlaa 2026-10-03);
# ALLOWED in fleet-plane-read must match.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
U=svc-hermes
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
say() { echo "── $* ──"; }
fail() { echo "✗ $*" >&2; exit 1; }

say "1/5 user fleetplane"
id fleetplane >/dev/null 2>&1 || useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin fleetplane
echo "   $(id fleetplane)"

say "2/5 /etc/fleet-plane"
install -d -o root -g fleetplane -m0750 /etc/fleet-plane
if [ -f /etc/fleet-plane/token ]; then
  chown root:fleetplane /etc/fleet-plane/token && chmod 0640 /etc/fleet-plane/token
  echo "   token present"
else
  echo "   no token yet — push it from the Mac (see header), then re-run"
fi

say "3/5 tools (root-owned)"
install -d -o root -g root -m0755 /usr/local/libexec
install -o root -g root -m0755 "${SRC}/fleet-plane-read" /usr/local/libexec/fleet-plane-read
install -o root -g root -m0755 "${SRC}/fleet-plane" /usr/local/bin/fleet-plane

say "4/5 sudoers"
SUD=/etc/sudoers.d/fleet-plane
TMP="$(mktemp)"
cat > "$TMP" <<EOF
# Managed by core/elmaati/deploy/hq/fleet-plane/install.sh
# svc-hermes may run ONE read-only binary as fleetplane (the Plane token holder). Nothing else.
Defaults:${U} !use_pty
${U} ALL=(fleetplane) NOPASSWD: /usr/local/libexec/fleet-plane-read
${U} ALL=(fleetplane) NOPASSWD: /usr/local/libexec/fleet-plane-read *
EOF
visudo -cqf "$TMP" || fail "sudoers rule does not validate"
install -o root -g root -m0440 "$TMP" "$SUD"; rm -f "$TMP"
echo "   $(sudo -l -U "$U" | grep -c fleet-plane-read) rule(s) for ${U}"

say "5/5 checks"
as() { sudo -u "$U" -H "$@"; }
as test -r /etc/fleet-plane/token && fail "svc-hermes can read the token"
echo "   svc-hermes cannot read the token"
as sudo -n -u fleetplane /bin/cat /etc/fleet-plane/token >/dev/null 2>&1 && fail "svc-hermes can run other commands as fleetplane"
as sudo -n -u root /usr/local/libexec/fleet-plane-read projects >/dev/null 2>&1 && fail "svc-hermes can run the tool as root"
echo "   no other sudo: cat as fleetplane refused, root refused"
grep -qE "method=|Request\([^)]*method" /usr/local/libexec/fleet-plane-read && fail "the tool names an HTTP method other than the default GET"
r="$(as /usr/local/bin/fleet-plane issues LIM || true)"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["exit_code"]==4, r; print("   project outside the six refused")'
r="$(as /usr/local/bin/fleet-plane issues ADOL --limit=9999 || true)"
echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["exit_code"]==4, r; print("   bad argument refused")'
if [ -f /etc/fleet-plane/token ]; then
  r="$(as /usr/local/bin/fleet-plane projects)"
  echo "$r" | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["ok"], r; print("   projects:", " ".join(p["key"] for p in r["projects"]))'
fi
echo "   done. Calls are logged: journalctl -t fleet-plane"
