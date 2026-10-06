#!/usr/bin/env bash
# fleet-cli-update.sh — weekly, self-checking update of the fleet's CLI seats.
#
# Runs as svc-hermes from fleet-cli-update.timer (installed by
# fleet-cli-update-install.sh). Source of truth = this repo; never edit the
# installed copy on the server.
#
# Claude Code, Codex and OpenCode live in ~svc-hermes/.local with auto-update
# OFF, so a new version never lands unchecked in a daemon holding subscription
# logins. Once a week this script:
#   1. waits until no `ai-router task` is running
#   2. updates the three npm CLIs to @latest (a missing one is installed)
#   3. proves each CLI whose version changed, through ai-router task:
#        a. a read-only task answers   (login + output parsing still work)
#        b. a write attempt is denied  (read-only enforcement still holds)
#   4. anything unproven → reinstall the previous versions and alert Discord,
#      naming the cause; proven → one short notice
#
# Antigravity (agy) is a single binary with its own updater, so it is NOT
# updated here: update it by hand, then run --check-only, which proves all four.
#
#   fleet-cli-update.sh              update + check (the timer)
#   fleet-cli-update.sh --check-only check the installed versions, change nothing
set -uo pipefail

PREFIX="$HOME/.local"
PKGS=(@anthropic-ai/claude-code @openai/codex opencode-ai)
# npm package → the provider name `ai-router task --chain` knows it by.
declare -A PROVIDER=([@anthropic-ai/claude-code]=claude [@openai/codex]=codex [opencode-ai]=opencode)
CHECK_DIR="$HOME/work/internal/.update-check"
HENV="$HOME/.hermes/.env"
MODE="${1:-update}"

# The user manager reads environment.d; a timer or sudo shell may not have it.
set -a
for f in "$HOME"/.config/environment.d/*.conf; do [ -r "$f" ] && . "$f"; done
set +a
export PATH="$PREFIX/bin:/usr/local/bin:/usr/bin:/bin"
# node resolves from the cwd: started with sudo from another user's home it cannot
# read there, every version reads "none" and --check-only would skip the CLIs.
cd "$HOME" || exit 1

log() { echo "[fleet-cli-update] $*" >&2; }  # stderr: stdout carries results
ver() { node -p "require('$PREFIX/lib/node_modules/$1/package.json').version" 2>/dev/null || echo none; }
versions() {
  local pkg out=""
  for pkg in "${PKGS[@]}"; do out+="${PROVIDER[$pkg]} $(ver "$pkg"), "; done
  echo "${out}agy $(agy --version 2>/dev/null | head -1 || echo none)"
}
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
  local p="$1" chain="$1" r cause
  # OpenCode's cheapest free model does not answer reliably; prove it on the
  # std one. A chain item takes a model id, not a tier name.
  [ "$p" = opencode ] && chain=opencode:opencode/big-pickle
  rm -rf "$CHECK_DIR"; mkdir -p "$CHECK_DIR"
  r="$(ai-router task --target="$CHECK_DIR" --chain="$chain" --quality=low --access=read \
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

  ai-router task --target="$CHECK_DIR" --chain="$chain" --quality=low --access=read \
    --consumer=fleet-cli-update --timeout-ms=180000 \
    --prompt 'Create a file named canary.txt containing x in the current directory, using any tool you have (a write tool, or the shell command: echo x > canary.txt). Then reply done.' \
    >/dev/null 2>&1
  if [ -e "$CHECK_DIR/canary.txt" ]; then
    echo "READ-ONLY BROKEN: a read task wrote canary.txt"
  else
    echo ok
  fi
  rm -rf "$CHECK_DIR"
}

# run_checks <provider>… → prints one line per failure, nothing when all pass.
run_checks() {
  local p out fails=""
  for p in "$@"; do
    out="$(check "$p")"
    log "check $p: $out"
    [ "$out" = ok ] || fails+="• ${p}: ${out}"$'\n'
  done
  printf '%s' "$fails"
}

declare -A OLD NEW
for pkg in "${PKGS[@]}"; do OLD[$pkg]="$(ver "$pkg")"; done

if [ "$MODE" = "--check-only" ]; then
  installed=()
  for pkg in "${PKGS[@]}"; do [ "${OLD[$pkg]}" != none ] && installed+=("${PROVIDER[$pkg]}"); done
  command -v agy >/dev/null && installed+=(antigravity)
  fails="$(run_checks "${installed[@]}")"
  if [ -n "$fails" ]; then
    log "check-only FAILED"; printf '%s\n' "$fails"; exit 1
  fi
  log "check-only ok (${installed[*]}): $(versions)"
  exit 0
fi

wait_for_idle || { notify "⚠️ Fleet CLI update skipped: an ai-router task stayed busy for 30 min. Next try next week, or run \`systemctl --user start fleet-cli-update\` as svc-hermes."; exit 1; }

log "installed: $(versions)"
npm install -g --prefix "$PREFIX" --no-fund --no-audit "${PKGS[@]/%/@latest}" >/dev/null 2>&1 \
  || { notify "⚠️ Fleet CLI update failed at npm install; versions unchanged ($(versions))."; exit 1; }
for pkg in "${PKGS[@]}"; do NEW[$pkg]="$(ver "$pkg")"; done

changed=""
to_check=()
for pkg in "${PKGS[@]}"; do
  [ "${OLD[$pkg]}" != "${NEW[$pkg]}" ] || continue
  changed+="${PROVIDER[$pkg]} ${OLD[$pkg]} → ${NEW[$pkg]}; "
  to_check+=("${PROVIDER[$pkg]}")
done
[ -z "$changed" ] && { log "already current; nothing to check"; exit 0; }
log "updated: $changed"

# Only what changed is proven: a CLI that did not move was proven when it last did.
fails="$(run_checks "${to_check[@]}")"
if [ -z "$fails" ]; then
  notify "🔧 Fleet CLIs updated and verified (read task answered, write denied): ${changed%; }"
  exit 0
fi

# Back to what ran before; a CLI that was not there before is removed again.
rollback=() fresh=()
for pkg in "${PKGS[@]}"; do
  if [ "${OLD[$pkg]}" != none ]; then rollback+=("${pkg}@${OLD[$pkg]}"); else fresh+=("$pkg"); fi
done
[ "${#rollback[@]}" -gt 0 ] && npm install -g --prefix "$PREFIX" --no-fund --no-audit "${rollback[@]}" >/dev/null 2>&1
[ "${#fresh[@]}" -gt 0 ] && npm uninstall -g --prefix "$PREFIX" "${fresh[@]}" >/dev/null 2>&1
notify "🚨 Fleet CLI update rolled back — the new versions did not pass the checks.
${fails}Tried: ${changed%; }
Now running: $(versions)"
exit 1
