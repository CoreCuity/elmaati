#!/usr/bin/env bash
# hermes-nightly-restart.sh — the planned nightly gateway restart (upstream memory growth #58817).
#
# Runs as svc-hermes from hermes-gateway-restart.service; installed by hermes-fleet-fixes.sh step 6.
# Source of truth = this repo; never edit the installed copy on the server. Install from the Mac:
#   ssh corecuity-HQ 'sudo install -o svc-hermes -g svc-hermes -m0755 /dev/stdin \
#     /home/svc-hermes/.local/bin/hermes-nightly-restart.sh' < deploy/hq/hermes-nightly-restart.sh
#
# Hermes' own home-channel "⚠️ Hermes is shutting down" broadcast reads like an incident, so:
#   1. write a drain marker with suppress_notification=true → Hermes skips ONLY that broadcast
#      (chats with a task in flight still get their interrupt ping, and crashes stay loud)
#   2. post our own "planned restart" notice to the Discord + Telegram home channels
#   3. restart the gateway
#   4. clear the marker — it survives a gateway-only restart (same boot epoch) and would otherwise
#      park the fresh gateway in "draining" for up to an hour
# Remove this whole mechanism once an update fixes #58817.
set -uo pipefail

HH="${HERMES_HOME:-$HOME/.hermes}"
PY="${HH}/hermes-agent/venv/bin/python"
ENVF="${HH}/.env"

envval() { grep -m1 -E "^$1=" "$ENVF" | cut -d= -f2- | tr -d '"'"'"; }

drain() {
  (cd "${HH}/hermes-agent" && HERMES_HOME="$HH" "$PY" -c "
from gateway.drain_control import $1
$1($2)") || echo "drain-control $1 failed (continuing)" >&2
}

VERSION="$(cd "$HH" && timeout 30 "$PY" -m hermes_cli.main --version 2>/dev/null | head -1 | sed 's/^Hermes Agent //')"
VERSION="${VERSION:-unknown version}"
MSG="🔧 Planned nightly restart — nothing is wrong. This is the scheduled workaround for Hermes memory growth (upstream #58817); back in a few seconds.
📌 Reminder: when the next Hermes update lands (running ${VERSION}), check whether #58817 is fixed. If it is, remove hermes-gateway-restart.timer."

drain write_drain_request "principal='nightly-restart', suppress_notification=True"
trap 'drain clear_drain_request ""' EXIT

DTOK="$(envval DISCORD_BOT_TOKEN)"; DCH="$(envval DISCORD_HOME_CHANNEL)"
if [ -n "$DTOK" ] && [ -n "$DCH" ]; then
  "$PY" -c 'import json,sys; print(json.dumps({"content": sys.argv[1]}))' "$MSG" \
    | curl -fsS -o /dev/null -X POST "https://discord.com/api/v10/channels/${DCH}/messages" \
        -H "Authorization: Bot ${DTOK}" -H "Content-Type: application/json" --data-binary @- \
    || echo "discord notice failed (continuing)" >&2
fi

TTOK="$(envval TELEGRAM_BOT_TOKEN)"; TCH="$(envval TELEGRAM_HOME_CHANNEL)"
if [ -n "$TTOK" ] && [ -n "$TCH" ]; then
  curl -fsS -o /dev/null "https://api.telegram.org/bot${TTOK}/sendMessage" \
    --data-urlencode "chat_id=${TCH}" --data-urlencode "text=${MSG}" \
    || echo "telegram notice failed (continuing)" >&2
fi

/usr/bin/systemctl --user restart hermes-gateway.service
