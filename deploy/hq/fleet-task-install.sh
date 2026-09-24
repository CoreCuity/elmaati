#!/usr/bin/env bash
# fleet-task-install.sh — install fleet-task (the fleet's only door to a CLI run) on corecuity-HQ.
#
# Run as root, from the Mac (source of truth = this repo):
#   tar -C core/elmaati -czf - deploy/hq/fleet-task deploy/hq/skills/fleet-task deploy/hq/fleet-task-install.sh \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-task && sudo mkdir /root/fleet-task \
#         && sudo tar -C /root/fleet-task -xzf - && sudo bash /root/fleet-task/deploy/hq/fleet-task-install.sh'
#
# What it does (idempotent):
#   1. /usr/local/bin/fleet-task, root:root 0755 — policy the agent cannot edit
#   2. the fleet-task skill for Elmaati (default profile), root-owned like the SOULs
#   3. approvals.deny: block calling claude/codex directly (default + every profile),
#      so fleet-task stays the only way in. Config backed up first.
# Takes effect for the gateway at its next start (nightly 04:30, or a restart).
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
U=svc-hermes
H="/home/${U}"
HH="${H}/.hermes"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
say() { echo "── $* ──"; }

say "1/3 /usr/local/bin/fleet-task"
install -o root -g root -m0755 "${SRC}/deploy/hq/fleet-task" /usr/local/bin/fleet-task

say "2/3 skill: autonomous-ai-agents/fleet-task (root-owned)"
SK="${HH}/skills/autonomous-ai-agents/fleet-task"
install -d -o root -g root -m0755 "$SK"
install -o root -g root -m0644 "${SRC}/deploy/hq/skills/fleet-task/SKILL.md" "${SK}/SKILL.md"

say "3/3 approvals.deny: no direct claude/codex"
install -d -m0700 "${H}/backups/fleet-task-${TS}"
for cfg in "${HH}/config.yaml" "${HH}"/profiles/*/config.yaml; do
  [ -f "$cfg" ] || continue
  cp -p "$cfg" "${H}/backups/fleet-task-${TS}/$(echo "${cfg#${HH}/}" | tr / _)"
  sudo -u "$U" -H python3 - "$cfg" <<'PY'
import sys, yaml
path = sys.argv[1]
c = yaml.safe_load(open(path)) or {}
deny = c.setdefault("approvals", {}).setdefault("deny", [])
add = ["*claude -p*", "*claude --print*", "*bin/claude*", "*codex exec*", "*codex e *", "*bin/codex*"]
new = [p for p in add if p not in deny]
deny.extend(new)
yaml.safe_dump(c, open(path, "w"), sort_keys=False, allow_unicode=True)
print(f"   {path}: +{len(new)} deny rule(s), {len(deny)} total")
PY
done
chown -R "$U:$U" "${H}/backups/fleet-task-${TS}"

say "verify"
sudo -u "$U" -H /usr/local/bin/fleet-task --target="${H}/work/internal" --prompt=x --dry-run \
  | python3 -c 'import json,sys; r=json.load(sys.stdin); print("   dry-run:", "ok" if r["ok"] else r["error"])'
for bad in "--access=write" "--max-per-hour=0" "--target=/etc"; do
  out="$(sudo -u "$U" -H /usr/local/bin/fleet-task --target="${H}/work/internal" --prompt=x --dry-run "$bad" || true)"
  echo "$out" | python3 -c 'import json,sys; r=json.load(sys.stdin); print("   refused '"$bad"':", r["exit_code"] == 4)'
done
echo "   gateway picks up the skill + deny rules at its next start (nightly 04:30 or a restart)."
