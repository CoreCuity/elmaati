#!/usr/bin/env bash
# fleet-souls-install.sh — install the fleet's SOULs and Elmaati's CoreCuity skills on corecuity-HQ. Run as root.
#
# Run from the Mac (source of truth = this repo; never edit on the server):
#   tar -C core/elmaati -czf - agents deploy/hq/skills deploy/hq/fleet-souls-install.sh \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-souls && sudo mkdir /root/fleet-souls \
#         && sudo tar -C /root/fleet-souls -xzf - && sudo bash /root/fleet-souls/deploy/hq/fleet-souls-install.sh'
#
# What it does (idempotent):
#   1. SOUL of every profile (default = Elmaati, sentinel, ads, clerk), root:root 0644 — an agent cannot
#      edit its own instructions in place
#   2. every skill under deploy/hq/skills/, root-owned, into the default profile
#   3. remove skills this repo has retired (the July 2026 n8n/dashboard health skill)
# Takes effect for the gateway at its next start (nightly 04:30), or now with:
#   sudo -u svc-hermes XDG_RUNTIME_DIR=/run/user/$(id -u svc-hermes) systemctl --user start hermes-gateway-restart.service
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
U=svc-hermes
HH="/home/${U}/.hermes"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
say() { echo "── $* ──"; }

say "1/3 SOULs (root-owned)"
install -o root -g root -m0644 "${SRC}/agents/elmaati-soul.md" "${HH}/SOUL.md"
for p in sentinel ads clerk; do
  [ -d "${HH}/profiles/${p}" ] || { echo "✗ profile ${p} missing — run fleet-profiles.sh first" >&2; exit 1; }
  install -o root -g root -m0644 "${SRC}/agents/${p}-soul.md" "${HH}/profiles/${p}/SOUL.md"
done

say "2/3 skills (root-owned, default profile)"
# Category each repo skill is installed under.
declare -A CAT=( [fleet-task]=autonomous-ai-agents [fleet-health]=operations [fleet-vault]=operations )
for d in "${SRC}"/deploy/hq/skills/*/; do
  name="$(basename "$d")"
  [ -n "${CAT[$name]:-}" ] || { echo "✗ skill ${name} has no category in CAT" >&2; exit 1; }
  dst="${HH}/skills/${CAT[$name]}/${name}"
  install -d -o root -g root -m0755 "$dst"
  install -o root -g root -m0644 "${d}SKILL.md" "${dst}/SKILL.md"
  echo "   ${CAT[$name]}/${name}"
done

say "3/3 retired skills"
for old in operations/corecuity-ops-health-checks; do
  if [ -d "${HH}/skills/${old}" ]; then rm -rf "${HH}/skills/${old}"; echo "   ${old}: removed"; else echo "   ${old}: already gone"; fi
done

say "verify"
for f in "${HH}/SOUL.md" "${HH}"/profiles/*/SOUL.md "${HH}"/skills/*/fleet-*/SKILL.md; do
  printf '   %s %s %s\n' "$(stat -c '%U %a' "$f")" "$(sha256sum "$f" | cut -c1-16)" "${f#${HH}/}"
done
if grep -rlIiE 'n8n|server-architect|dashboard-v2' "${HH}/SOUL.md" "${HH}"/profiles/*/SOUL.md "${HH}"/skills/operations 2>/dev/null; then
  echo "✗ retired systems still named in the files above" >&2; exit 1
fi
echo "   no retired system named in any SOUL or operations skill."
echo "   gateway reads the new SOULs and skills at its next start (nightly 04:30 or a restart)."
