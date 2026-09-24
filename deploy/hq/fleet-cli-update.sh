#!/usr/bin/env bash
# fleet-cli-update.sh — weekly, self-checking update of the fleet's CLI seats.
#
# Runs as svc-hermes from fleet-cli-update.timer (installed by
# fleet-cli-update-install.sh). Source of truth = this repo; never edit the
# installed copy on the server.
#
# Claude Code and Codex live in ~svc-hermes/.local with auto-update OFF, so a
# new version never lands unchecked in a daemon holding subscription logins.
# Once a week this script:
#   1. waits until no `ai-router task` is running
#   2. updates both CLIs to @latest
#   3. if a version changed, proves each CLI through ai-router task:
#        a. a read-only task answers   (login + output parsing still work)
#        b. a write attempt is denied  (read-only enforcement still holds)
#   4. anything unproven → reinstall the previous versions and alert Discord,
#      naming the cause; proven → one short notice
#
#   fleet-cli-update.sh              update + check (the timer)
#   fleet-cli-update.sh --check-only check the installed versions, change nothing
set -uo pipefail

PREFIX="$HOME/.local"
PKGS=(@anthropic-ai/claude-code @openai/codex)
CHECK_DIR="$HOME/work/internal/.update-check"
HENV="$HOME/.hermes/.env"
MODE="${1:-update}"

# The user manager reads environment.d; a timer or sudo shell may not have it.
set -a
for f in "$HOME"/.config/environment.d/*.conf; do [ -r "$f" ] && . "$f"; done
set +a
export PATH="$PREFIX/bin:/usr/local/bin:/usr/bin:/bin"

log() { echo "[fleet-cli-update] $*"; }
ver() { node -p "require('$PREFIX/lib/node_modules/$1/package.json').version" 2>/dev/null || echo none; }
envval() { grep -m1 -E "^$1=" "$HENV" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"; }

notify() {
  local tok ch
  tok="$(envval DISCORD_BOT_TOKEN)"; ch="$(envval DISCORD_HOME_CHANNEL)"
  log "notify: $1"
  [ -n "$tok" ] && [ -n "$ch" ] || { log "no Discord credentials; alert only in the journal"; return 0; }
  node -e 'process.stdout.write(JSON.stringify({content: process.argv[1]}))' "$1" \
    | curl -fsS -o /dev/null -X POST "https://discord.com/api/v10/channels/${ch}/messages" \
        -H "Authorization: Bot ${tok}" -H "Content-Type: application/json" --data-binary @- \
    || log "discord notice failed"
}

wait_for_idle() {
  local i
  for i in $(seq 1 60); do
    ai-router doctor --target="$HOME" 2>/dev/null | grep -q ' 0 slot(s) busy' && return 0
    sleep 30
  done
  return 1
}

# check <provider> → prints "ok" or a one-line cause; never exits the script.
check() {
  local p="$1" r cause
  rm -rf "$CHECK_DIR"; mkdir -p "$CHECK_DIR"
  r="$(ai-router task --target="$CHECK_DIR" --chain="$p" --quality=low --access=read \
        --consumer=fleet-cli-update --timeout-ms=180000 \
        --prompt 'Reply with exactly the word FLEET-OK and nothing else.' 2>/dev/null)"
  cause="$(node -e '
    let r; try { r = JSON.parse(process.argv[1]); } catch { console.log("no receipt from ai-router"); process.exit(); }
    const a = (r.attempts || []).at(-1) || {};
    if (r.ok && /FLEET-OK/.test(r.output || "")) console.log("ok");
    else if (a.category === "auth") console.log(`login missing or expired (${a.error})`);
    else if (a.category === "quota") console.log(`subscription limit hit, could not verify (${a.error})`);
    else if (r.ok) console.log(`answer not parsed: ${JSON.stringify((r.output || "").slice(0, 120))}`);
    else console.log(r.error || "unknown failure");
  ' "$r")"
  [ "$cause" = ok ] || { echo "read task: $cause"; return; }

  ai-router task --target="$CHECK_DIR" --chain="$p" --quality=low --access=read \
    --consumer=fleet-cli-update --timeout-ms=180000 \
    --prompt 'Create a file named canary.txt containing x in the current directory, using any tool you have. Then reply done.' \
    >/dev/null 2>&1
  if [ -e "$CHECK_DIR/canary.txt" ]; then
    echo "READ-ONLY BROKEN: a read task wrote canary.txt"
  else
    echo ok
  fi
  rm -rf "$CHECK_DIR"
}

run_checks() {
  local p out fails=""
  for p in claude codex; do
    out="$(check "$p")"
    log "check $p: $out"
    [ "$out" = ok ] || fails+="• ${p}: ${out}"$'\n'
  done
  printf '%s' "$fails"
}

declare -A OLD NEW
for pkg in "${PKGS[@]}"; do OLD[$pkg]="$(ver "$pkg")"; done

if [ "$MODE" = "--check-only" ]; then
  fails="$(run_checks)"
  if [ -n "$fails" ]; then
    log "check-only FAILED"; printf '%s\n' "$fails"; exit 1
  fi
  log "check-only ok: claude ${OLD[@anthropic-ai/claude-code]}, codex ${OLD[@openai/codex]}"
  exit 0
fi

wait_for_idle || { notify "⚠️ Fleet CLI update skipped: an ai-router task stayed busy for 30 min. Next try next week, or run \`systemctl --user start fleet-cli-update\` as svc-hermes."; exit 1; }

log "installed: claude ${OLD[@anthropic-ai/claude-code]}, codex ${OLD[@openai/codex]}"
npm install -g --prefix "$PREFIX" --no-fund --no-audit "${PKGS[@]/%/@latest}" >/dev/null 2>&1 \
  || { notify "⚠️ Fleet CLI update failed at npm install; versions unchanged (claude ${OLD[@anthropic-ai/claude-code]}, codex ${OLD[@openai/codex]})."; exit 1; }
for pkg in "${PKGS[@]}"; do NEW[$pkg]="$(ver "$pkg")"; done

changed=""
for pkg in "${PKGS[@]}"; do
  [ "${OLD[$pkg]}" != "${NEW[$pkg]}" ] && changed+="${pkg##*/} ${OLD[$pkg]} → ${NEW[$pkg]}; "
done
[ -z "$changed" ] && { log "already current; nothing to check"; exit 0; }
log "updated: $changed"

fails="$(run_checks)"
if [ -z "$fails" ]; then
  notify "🔧 Fleet CLIs updated and verified (read task answered, write denied): ${changed%; }"
  exit 0
fi

rollback=()
for pkg in "${PKGS[@]}"; do [ "${OLD[$pkg]}" != none ] && rollback+=("${pkg}@${OLD[$pkg]}"); done
npm install -g --prefix "$PREFIX" --no-fund --no-audit "${rollback[@]}" >/dev/null 2>&1
restored="claude $(ver @anthropic-ai/claude-code), codex $(ver @openai/codex)"
notify "🚨 Fleet CLI update rolled back — the new versions did not pass the checks.
${fails}Tried: ${changed%; }
Now running: ${restored}"
exit 1
