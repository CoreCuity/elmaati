#!/usr/bin/env bash
# hermes-fleet-fixes.sh — fleet v1 Phase 0 fixes for the Hermes body on corecuity-HQ.
#
# Run from the Mac (source of truth = this repo; never edit on the server). Run DETACHED, because
# apt/needrestart has killed an SSH session mid-script before:
#   ssh corecuity-HQ 'sudo install -m0700 /dev/stdin /root/hermes-fleet-fixes.sh \
#     && sudo systemd-run --unit=hermes-fixes --collect -p Type=oneshot --no-block \
#        /bin/bash /root/hermes-fleet-fixes.sh' < core/elmaati/deploy/hq/hermes-fleet-fixes.sh
#   ssh corecuity-HQ 'journalctl -u hermes-fixes -f'
#
# What it does, in order:
#   1. backup state.db / kanban.db / cron/executions.db (sqlite online backup) + config + envs
#   2. stop the gateway and backend
#   3. drop the duplicated TELEGRAM_* block from each profile .env  → unblocks multiplex mode
#      (profiles default/analyst/coder/scout all carried the SAME bot token, which forces the
#      gateway into standalone mode: "the bot can only belong to one profile")
#   4. hermes update            → v0.21.3 is 1751 commits behind; brings the SQLite WAL-reset
#                                 handling merged 2026-09-16. All three DBs are currently in WAL
#                                 mode on system SQLite 3.45.1, which IS in the affected range.
#   5. write fleet config: explicit gateway.multiplex_profiles, approvals deny-globs, safe defaults
#   6. install a nightly gateway restart timer (upstream memory-growth issue #58817)
#   7. restart, then verify: doctor, units, platform connections
set -euo pipefail

U=svc-hermes
H="/home/${U}"
HH="${H}/.hermes"
TS="$(date -u +%Y%m%d-%H%M%S)"
BK="${H}/backups/phase0-${TS}"

[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
UID_N="$(id -u "$U")"
as_u() { sudo -u "$U" -H env XDG_RUNTIME_DIR="/run/user/${UID_N}" \
         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_N}/bus" \
         PATH="${H}/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"; }
say() { echo "── $* ──"; }

# ── 1. Backup ───────────────────────────────────────────────────────────────
say "1/7 backup → $BK"
as_u mkdir -p "$BK"
as_u python3 - "$HH" "$BK" <<'PY'
import sqlite3, sys, os, shutil
hh, bk = sys.argv[1], sys.argv[2]
for rel in ("state.db", "kanban.db", "cron/executions.db"):
    src = os.path.join(hh, rel)
    if not os.path.exists(src):
        print(f"   skip {rel} (absent)"); continue
    dst = os.path.join(bk, rel.replace("/", "_"))
    s = sqlite3.connect(f"file:{src}?mode=ro", uri=True)
    d = sqlite3.connect(dst)
    with d:
        s.backup(d)          # online backup: consistent even with WAL + live writers
    s.close(); d.close()
    print(f"   backed up {rel} -> {os.path.basename(dst)} ({os.path.getsize(dst)} B)")
for rel in ("config.yaml", "SOUL.md", ".env"):
    src = os.path.join(hh, rel)
    if os.path.exists(src):
        shutil.copy2(src, os.path.join(bk, rel.replace("/", "_")))
        print(f"   copied {rel}")
PY
for p in analyst coder scout; do
  [ -f "${HH}/profiles/${p}/.env" ] && as_u cp -p "${HH}/profiles/${p}/.env" "${BK}/profile-${p}.env"
done
as_u sh -c "ls -la '$BK'"

# ── 2. Stop services ────────────────────────────────────────────────────────
say "2/7 stop gateway + backend"
as_u systemctl --user stop hermes-gateway.service hermes-serve.service || true

# ── 3. De-duplicate the bot tokens ──────────────────────────────────────────
say "3/7 remove duplicated TELEGRAM_* from profile .env files"
for p in analyst coder scout; do
  f="${HH}/profiles/${p}/.env"
  [ -f "$f" ] || continue
  as_u python3 - "$f" <<'PY'
import re, sys
f = sys.argv[1]
keys = ("TELEGRAM_BOT_TOKEN", "TELEGRAM_ALLOWED_USERS",
        "TELEGRAM_HOME_CHANNEL", "TELEGRAM_HOME_CHANNEL_NAME",
        "DISCORD_BOT_TOKEN", "DISCORD_ALLOWED_USERS",
        "DISCORD_HOME_CHANNEL", "DISCORD_HOME_CHANNEL_NAME",
        "DISCORD_FREE_RESPONSE_CHANNELS")
out, n = [], 0
for line in open(f).read().splitlines():
    m = re.match(r'\s*([A-Z_]+)\s*=', line)
    if m and m.group(1) in keys:
        out.append("# [fleet v1 2026-09-19] removed — the bot belongs to the default profile; "
                   "route here with gateway.profile_routes instead")
        out.append("# " + line)
        n += 1
    else:
        out.append(line)
open(f, "w").write("\n".join(out) + "\n")
print(f"   {f}: commented {n} line(s)")
PY
  chown "$U:$U" "$f"; chmod 600 "$f"
done

# ── 4. Update Hermes (the SQLite fix) ───────────────────────────────────────
say "4/7 hermes update (SQLite WAL-reset handling; 0.21.3 was 1751 commits behind)"
as_u "${H}/.local/bin/hermes" update 2>&1 | tail -25 || { echo "✗ update failed — see above"; exit 1; }
as_u "${H}/.local/bin/hermes" --version 2>&1 | head -2

# ── 5. Fleet config ─────────────────────────────────────────────────────────
say "5/7 write fleet config keys"
as_u python3 - "$HH/config.yaml" <<'PY'
import sys, yaml, shutil, datetime
p = sys.argv[1]
shutil.copy2(p, p + ".pre-fleet-" + datetime.date.today().isoformat())
c = yaml.safe_load(open(p)) or {}

gw = c.setdefault("gateway", {})
gw["multiplex_profiles"] = True          # explicit: one process, profiles share the bot
gw.setdefault("profile_routes", [])      # filled when the Discord HQ channels exist

ap = c.setdefault("approvals", {})
ap["mode"] = "smart"                     # aux LLM auto-approves low-risk only
ap["cron_mode"] = "deny"                 # nobody is watching a cron job
ap["unattended_mode"] = "deny"
ap["single_query_mode"] = "deny"
ap["mcp_reload_confirm"] = True
# Hard blocks: these match even under mode=off. Guardrails in config, not in a prompt.
deny = set(ap.get("deny") or [])
deny.update([
    "git push --force*", "git push -f*", "git reset --hard*",
    "rm -rf /*", "rm -rf ~*", "rm -rf .*",
    "*curl*|*sh*", "*wget*|*sh*",
    "*DROP TABLE*", "*DROP DATABASE*", "*TRUNCATE*",
    "sudo *", "chmod -R 777*",
    "*docker*rm -f*", "*systemctl*disable*",
])
ap["deny"] = sorted(deny)
ap["smart_policy"] = (
    "ESCALATE anything that: writes to a client system or client server; sends a message, email "
    "or post that leaves CoreCuity; changes DNS, ad spend, billing or production; force-pushes or "
    "deletes history; touches another tenant's data. Client-facing and irreversible actions are "
    "never auto-approved, whatever the reason given."
)

c.setdefault("security", {})["allow_private_urls"] = False   # no SSRF into the LAN

yaml.safe_dump(c, open(p, "w"), sort_keys=False, allow_unicode=True)
print("   gateway.multiplex_profiles:", c["gateway"]["multiplex_profiles"])
print("   approvals.mode/cron/unattended:", ap["mode"], ap["cron_mode"], ap["unattended_mode"])
print("   approvals.deny rules:", len(ap["deny"]))
PY

# ── 6. Nightly gateway restart (upstream memory growth #58817) ──────────────
say "6/7 nightly gateway restart timer"
UD="${H}/.config/systemd/user"
as_u mkdir -p "$UD"
cat > "${UD}/hermes-gateway-restart.service" <<'EOF'
# Managed by core/elmaati/deploy/hq/hermes-fleet-fixes.sh
[Unit]
Description=Nightly restart of the Hermes gateway (upstream memory growth #58817)
[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl --user restart hermes-gateway.service
EOF
cat > "${UD}/hermes-gateway-restart.timer" <<'EOF'
[Unit]
Description=Restart the Hermes gateway nightly at 04:30
[Timer]
OnCalendar=*-*-* 04:30:00
Persistent=true
RandomizedDelaySec=5min
[Install]
WantedBy=timers.target
EOF
chown "$U:$U" "${UD}"/hermes-gateway-restart.*
as_u systemctl --user daemon-reload
as_u systemctl --user enable --now hermes-gateway-restart.timer

# ── 7. Restart + verify ─────────────────────────────────────────────────────
say "7/7 restart + verify"
as_u systemctl --user start hermes-serve.service hermes-gateway.service
sleep 25
as_u systemctl --user --no-pager --plain --no-legend list-units 'hermes-*'
echo "-- doctor --"
as_u "${H}/.local/bin/hermes" doctor 2>&1 | grep -iE "sqlite|wal|version|config version|✗|⚠" | head -12
echo "-- platforms --"
grep -aiE "Connected as|Connected to|Gateway running|duplicate_credential|standalone" "${HH}/logs/gateway.log" 2>/dev/null | tail -6
echo "✓ fixes applied. Backup: $BK"
