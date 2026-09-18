#!/usr/bin/env bash
# restore-hermes.sh — bring Elmaati's Hermes body back on corecuity-HQ as svc-hermes,
# restored from the server-architect insurance archive (2026-08-27).
#
# Prereq: core/infra/provision/new-agent.sh has created svc-hermes.
# Run from the Mac (source of truth = this repo; never edit on the server):
#   ssh corecuity-HQ 'sudo bash -s' < core/elmaati/deploy/hq/restore-hermes.sh
#
# Idempotent. Does NOT start the gateway (START=1 to start it) and does NOT restore auth.json:
# the Codex OAuth login is re-done by the operator with a device flow (HERMES-MAC-RELOCATION.md
# rule: re-authenticate, never copy OAuth tokens between hosts).
set -euo pipefail

ARCHIVE="${ARCHIVE:-/srv/attic/architect-2026-08-27/home-elmaati.tar.zst}"
U=svc-hermes
H="/home/${U}"
OLD_HOME=/home/elmaati
START="${START:-0}"

[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
id "$U" >/dev/null || { echo "✗ $U missing — run new-agent.sh hermes first" >&2; exit 1; }
UID_N="$(id -u "$U")"
as_u() { sudo -u "$U" -H env XDG_RUNTIME_DIR="/run/user/${UID_N}" \
         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_N}/bus" \
         PATH="${H}/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"; }

# ── 1. Box prerequisites ────────────────────────────────────────────────────
dpkg -s ripgrep ffmpeg zstd git >/dev/null 2>&1 || \
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q ripgrep ffmpeg zstd git >/dev/null
# IPv6 on this box is unroutable but DNS returns AAAA first; Python clients (httpx) then hang on
# the v6 attempt. Prefer IPv4 box-wide (replaces the per-unit NODE_OPTIONS workaround need).
grep -q '^precedence ::ffff:0:0/96  *100' /etc/gai.conf || \
  printf '\n# corecuity: IPv6 unroutable on this host — prefer IPv4 (2026-09-18)\nprecedence ::ffff:0:0/96  100\n' >> /etc/gai.conf

# ── 2. Install Hermes (fresh code; state comes from the archive) ────────────
if [ ! -x "${H}/.local/bin/hermes" ]; then
  echo "→ installing Hermes as $U"
  as_u bash -c 'cd ~ && curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash' \
    > "${H}/install.log" 2>&1 || { tail -30 "${H}/install.log"; exit 1; }
  chown "$U:$U" "${H}/install.log"
fi
echo "✓ hermes: $(as_u "${H}/.local/bin/hermes" --version 2>/dev/null | head -1)"

# ── 3. Restore state from the archive ───────────────────────────────────────
if [ ! -f "${H}/.hermes/.restored-from-attic" ]; then
  TMP="$(mktemp -d /root/hermes-restore.XXXXXX)"
  trap 'rm -rf "$TMP"' EXIT
  tar -xf "$ARCHIVE" --zstd -C "$TMP" home/elmaati/.hermes
  SRC="$TMP/home/elmaati/.hermes"
  rsync -a \
    --exclude 'hermes-agent/' --exclude 'bin/' --exclude 'auth.json' --exclude 'auth.lock' \
    --exclude '*.pid' --exclude '*.lock' --exclude 'gateway_state.json' \
    --exclude 'logs/' --exclude 'cache/' --exclude 'image_cache/' --exclude 'audio_cache/' \
    --exclude 'sandboxes/' --exclude 'sessions/request_dump_*' --exclude '.update_check' \
    "$SRC/" "${H}/.hermes/"
  # Re-home absolute paths in text config (never touch sqlite files).
  grep -rlI --exclude='*.db*' "$OLD_HOME" "${H}/.hermes" 2>/dev/null | grep -v '/hermes-agent/' | \
    while read -r f; do sed -i "s#${OLD_HOME}#${H}#g" "$f"; done
  date -u +%FT%TZ > "${H}/.hermes/.restored-from-attic"
  chown -R "$U:$U" "${H}/.hermes"
  chmod 0600 "${H}/.hermes/.env" "${H}"/.hermes/profiles/*/.env 2>/dev/null || true
  echo "✓ state restored from $(basename "$ARCHIVE")"
else
  echo "• state already restored ($(cat "${H}/.hermes/.restored-from-attic")) — skipping"
fi

# ── 4. Services (user units under svc-hermes) ───────────────────────────────
UNIT_DIR="${H}/.config/systemd/user"
as_u mkdir -p "$UNIT_DIR"
# Gateway unit = what `hermes gateway install` generated on server-architect (v0.18.2), re-homed.
cat > "${UNIT_DIR}/hermes-gateway.service" <<'EOF'
# Managed by core/elmaati/deploy/hq/restore-hermes.sh
[Unit]
Description=Hermes Agent Gateway - Messaging Platform Integration
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=%h/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run
WorkingDirectory=%h/.hermes
Environment="PATH=%h/.hermes/hermes-agent/venv/bin:%h/.hermes/hermes-agent/node_modules/.bin:%h/.local/bin:/usr/local/bin:/usr/bin:/bin"
Environment="VIRTUAL_ENV=%h/.hermes/hermes-agent/venv"
Environment="HERMES_HOME=%h/.hermes"
Restart=always
RestartSec=5
RestartForceExitStatus=75
RestartPreventExitStatus=78
KillMode=mixed
KillSignal=SIGTERM
ExecReload=/bin/kill -USR1 $MAINPID
ExecStopPost=-%h/.hermes/hermes-agent/venv/bin/python -m gateway.cgroup_cleanup
TimeoutStopSec=90
NoNewPrivileges=yes

[Install]
WantedBy=default.target
EOF
cat > "${UNIT_DIR}/hermes-serve.service" <<'EOF'
# Managed by core/elmaati/deploy/hq/restore-hermes.sh
[Unit]
Description=Elmaati backend (hermes serve, loopback only)
After=network-online.target

[Service]
ExecStart=%h/.local/bin/hermes serve --host 127.0.0.1 --port 9119
Restart=on-failure
RestartSec=10
NoNewPrivileges=yes

[Install]
WantedBy=default.target
EOF
chown "$U:$U" "${UNIT_DIR}"/hermes-*.service
as_u systemctl --user daemon-reload
as_u systemctl --user enable hermes-serve.service hermes-gateway.service >/dev/null 2>&1 || true

if [ "$START" = "1" ]; then
  as_u systemctl --user restart hermes-serve.service hermes-gateway.service
  sleep 5
fi
as_u systemctl --user --no-pager --plain list-units 'hermes-*' || true
echo "✓ done. Next: operator runs the Codex device flow, then START=1."
