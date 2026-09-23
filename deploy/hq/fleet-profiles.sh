#!/usr/bin/env bash
# fleet-profiles.sh — the fleet v1 roster on corecuity-HQ (docs/architecture/fleet-v1.md §3). Run as root.
#
# Run from the Mac (source of truth = this repo; never edit on the server):
#   tar -C core/elmaati -czf - agents/sentinel-soul.md agents/ads-soul.md agents/clerk-soul.md deploy/hq/fleet-profiles.sh \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-profiles && sudo mkdir /root/fleet-profiles \
#         && sudo tar -C /root/fleet-profiles -xzf - && sudo bash /root/fleet-profiles/deploy/hq/fleet-profiles.sh'
# Then re-run fleet-audit/install.sh so the new homes get the tool-call log (it also restarts the gateway quietly).
#
# What it does (idempotent):
#   1. retire the unused pre-fleet profiles (analyst, coder, scout): full tar archive under /root/hermes-archive,
#      then `hermes profile delete` — refuses if any of them has sessions or memories
#   2. create sentinel, ads, clerk (no bundled skills) with their SOUL (root-owned: an agent cannot rewrite
#      its own instructions), the default profile's approvals + security blocks, and a per-role toolset deny-list
#   3. allowlist both founders on Discord (decision 2026-09-19)
# Workers get NO model credentials here: each needs its own login/key (never a copy of the default auth.json —
# a shared OAuth refresh token can log Elmaati out). Until then they are not routed (gateway.profile_routes).
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
U=svc-hermes
H="/home/${U}"
HH="${H}/.hermes"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
ARCH="/root/hermes-archive/${TS}-profiles"
DISCORD_FOUNDERS="900078539188109414,672208729101303819"   # Najlaa, Massine
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
UID_N="$(id -u "$U")"
as_u() { sudo -u "$U" -H env XDG_RUNTIME_DIR="/run/user/${UID_N}" HERMES_HOME="${HH}" "$@"; }
hermes() { (cd "$HH" && as_u "${HH}/hermes-agent/venv/bin/python" -m hermes_cli.main "$@"); }
say() { echo "── $* ──"; }

say "1/3 retire pre-fleet profiles"
for p in analyst coder scout; do
  d="${HH}/profiles/${p}"
  [ -d "$d" ] || { echo "   ${p}: already gone"; continue; }
  used="$(find "$d/sessions" "$d/memories" -type f 2>/dev/null | head -1 || true)"
  [ -z "$used" ] || { echo "✗ ${p} has sessions/memories (${used}) — not retiring it" >&2; exit 1; }
  install -d -m0700 "$ARCH"
  [ -f "${ARCH}/${p}.tgz" ] || tar -C "${HH}/profiles" -czf "${ARCH}/${p}.tgz" "$p"
  rm -rf "${d}/plugins/fleet-audit"   # root-owned (fleet-audit install) — svc-hermes cannot remove it
  if [ -f "${d}/config.yaml" ]; then hermes profile delete -y "$p" | sed "s/^/   /"; else rm -rf "$d"; fi
  echo "   ${p}: archived → ${ARCH}/${p}.tgz, deleted"
done

say "2/3 create sentinel, ads, clerk"
declare -A DESC=(
  [sentinel]="Read-only watch: backups, TLS, domains, tokens, reboots, disk, services, endpoints, storefront checks. Cause-naming alerts. Never writes."
  [ads]="Growth analyst: daily Meta audit per client reconciled against store order counts; anomalies, feed/pixel health, budget proposals. Proposes only."
  [clerk]="Back office: billing ledger, client-inputs tracker, Plane hygiene, monthly report assembly, drafts from templates. Drafts, never sends."
)
for p in sentinel ads clerk; do
  if [ -d "${HH}/profiles/${p}" ]; then echo "   ${p}: exists"; else
    hermes profile create "$p" --no-skills --description "${DESC[$p]}" | sed "s/^/   /"
  fi
  install -o root -g root -m0644 "${SRC}/agents/${p}-soul.md" "${HH}/profiles/${p}/SOUL.md"
done

# Per-role deny-lists (agent.disabled_toolsets is authoritative over every platform). Common to all workers:
# no browsing/computer use/media, no self-scheduling (Elmaati owns cron), no delegation, no account connecting.
as_u python3 - "$HH" <<'PY'
import sys, yaml
hh = sys.argv[1]
base = yaml.safe_load(open(f"{hh}/config.yaml"))
common = ["browser", "computer_use", "image_gen", "video", "video_gen", "tts", "stt", "vision", "x_search",
          "homeassistant", "spotify", "yuanbao", "delegation", "cronjob", "connections", "code_execution"]
extra = {
    "sentinel": ["file", "web"],             # reads through terminal: ssh fleetwatch@… fleet-status, curl
    "ads":      ["terminal", "file", "web"], # Meta MCP + store counts only (added with its skill)
    "clerk":    ["terminal", "web"],         # ledger/draft files + Plane MCP (added with its skill)
}
for p, more in extra.items():
    path = f"{hh}/profiles/{p}/config.yaml"
    c = yaml.safe_load(open(path)) or {}
    c.setdefault("agent", {})["disabled_toolsets"] = sorted(set(common + more))
    c["approvals"] = base["approvals"]
    c["security"] = base.get("security", {})
    yaml.safe_dump(c, open(path, "w"), sort_keys=False, allow_unicode=True)
    print(f"   {p}: disabled_toolsets={len(c['agent']['disabled_toolsets'])}, approvals.mode={c['approvals']['mode']}")
PY

say "3/3 founders on the Discord allowlist"
sed -i -E "s/^DISCORD_ALLOWED_USERS=.*/DISCORD_ALLOWED_USERS=${DISCORD_FOUNDERS}/" "${HH}/.env"
grep -E "^DISCORD_ALLOWED_USERS=" "${HH}/.env" | sed 's/^/   /'
hermes profile list 2>&1 | sed 's/^/   /'
