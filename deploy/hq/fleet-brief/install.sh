#!/usr/bin/env bash
# install.sh — Elmaati's 08:00 brief (fleet-v1 §3, §10 phase 1) on corecuity-HQ. Run as root; idempotent.
#
# Run from the Mac (source of truth = this repo; never edit on the server). The fleet-brief SKILL is
# installed by fleet-souls-install.sh first; this script installs the facts script and the cron job:
#   COPYFILE_DISABLE=1 tar -C core/elmaati/deploy/hq -czf - fleet-brief \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-brief && sudo tar -C /root -xzf - \
#         && sudo bash /root/fleet-brief/install.sh && sudo rm -rf /root/fleet-brief'
#
#   1. ~/.hermes/scripts/fleet-brief-facts.py, root-owned: the only material the brief is written from
#      (Sentinel digest, fleet-plane, the vault). The model phrases; it does not fetch.
#   2. Hermes cron job "fleet-brief": 08:00 every day (Hermes timezone = Africa/Casablanca),
#      skill fleet-brief, delivered to #briefing. Failures are delivered there too.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
U=svc-hermes
HH="/home/${U}/.hermes"
NAME=fleet-brief
SCHEDULE="0 8 * * *"
DELIVER="discord:1552185205010337862"   # #briefing, core/elmaati/deploy/hq/fleet-discord.yaml
PROMPT="Write today's 08:00 brief for the founders, following the fleet-brief skill exactly. Use only the facts block below; do not call any tools. Post nothing but the brief itself."
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
say() { echo "── $* ──"; }
fail() { echo "✗ $*" >&2; exit 1; }
hermes_() { sudo -u "$U" -H env HERMES_HOME="$HH" PATH="/home/${U}/.local/bin:/usr/local/bin:/usr/bin:/bin" bash -c 'cd "$HERMES_HOME" && hermes "$@"' _ "$@"; }

[ -f "${HH}/skills/operations/fleet-brief/SKILL.md" ] || fail "skill fleet-brief missing — run fleet-souls-install.sh first"

say "1/2 facts script (root-owned)"
install -d -o "$U" -g "$U" -m0755 "${HH}/scripts"
install -o root -g root -m0644 "${SRC}/fleet-brief-facts.py" "${HH}/scripts/fleet-brief-facts.py"
sudo -u "$U" -H python3 -m py_compile "${HH}/scripts/fleet-brief-facts.py" 2>/dev/null || python3 -m py_compile "${HH}/scripts/fleet-brief-facts.py"
rm -rf "${HH}/scripts/__pycache__"

say "2/2 cron job ${NAME}"
ID="$(hermes_ cron list 2>/dev/null | python3 -c '
import re, sys
t = sys.stdin.read()
for block in re.split(r"\n(?=\S)", t):
    if re.search(r"\b'"${NAME}"'\b", block):
        m = re.search(r"\b([0-9a-f]{8,}|job_[\w-]+)\b", block)
        if m: print(m.group(1)); break
')"
ARGS=(--name "$NAME" --deliver "$DELIVER" --skill fleet-brief --script fleet-brief-facts.py)
if [ -n "$ID" ]; then
  hermes_ cron edit "$ID" --schedule "$SCHEDULE" --prompt "$PROMPT" "${ARGS[@]}" >/dev/null
  echo "   updated job ${ID}"
else
  hermes_ cron create "${ARGS[@]}" "$SCHEDULE" "$PROMPT"
fi
hermes_ cron list 2>&1 | sed 's/^/   /'
echo "   test now (posts to #briefing):  hermes cron run <id>   — as ${U}, from ${HH}"
