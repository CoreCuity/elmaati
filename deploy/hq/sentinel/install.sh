#!/usr/bin/env bash
# install.sh — Sentinel v0 on corecuity-HQ (fleet-v1 §3). Run as root; idempotent.
#
# Run from the Mac (source of truth = this repo; never edit on the server):
#   tar -C core/elmaati/deploy/hq -czf - sentinel \
#     | ssh corecuity-HQ 'sudo rm -rf /root/sentinel && sudo tar -C /root -xzf - && sudo bash /root/sentinel/install.sh'
#
#   1. check + config → /usr/local/lib/sentinel (root-owned: svc-hermes runs it, cannot change what it watches)
#   2. svc-hermes user timers: sentinel-check every 15 min, sentinel-digest daily 08:00
#      (user units, so `fleet-kill contain` stops the watch with the rest of the fleet)
#   3. dry run as svc-hermes
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
U=svc-hermes
H="/home/${U}"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
UID_N="$(id -u "$U")"
as_u() { sudo -u "$U" -H env XDG_RUNTIME_DIR="/run/user/${UID_N}" "$@"; }
say() { echo "── $* ──"; }

say "1/3 files → /usr/local/lib/sentinel"
install -d -m0755 /usr/local/lib/sentinel
install -m0755 "${SRC}/sentinel-check" /usr/local/lib/sentinel/sentinel-check
install -m0644 "${SRC}/sentinel.yaml" /usr/local/lib/sentinel/sentinel.yaml

say "2/3 svc-hermes timers"
UD="${H}/.config/systemd/user"
as_u mkdir -p "$UD"
cat > "${UD}/sentinel-check.service" <<'EOF'
# Managed by core/elmaati/deploy/hq/sentinel/install.sh
[Unit]
Description=Sentinel v0 — fleet read-only watch (alerts to #infra-alerts)
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/lib/sentinel/sentinel-check
TimeoutStartSec=5min
EOF
cat > "${UD}/sentinel-check.timer" <<'EOF'
[Unit]
Description=Run the Sentinel watch every 15 minutes
[Timer]
OnBootSec=3min
OnUnitActiveSec=15min
[Install]
WantedBy=timers.target
EOF
cat > "${UD}/sentinel-digest.service" <<'EOF'
# Managed by core/elmaati/deploy/hq/sentinel/install.sh
[Unit]
Description=Sentinel v0 — daily digest (dead-man signal)
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/lib/sentinel/sentinel-check --digest
TimeoutStartSec=5min
EOF
cat > "${UD}/sentinel-digest.timer" <<'EOF'
[Unit]
Description=Sentinel daily digest at 08:00
[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
chown "$U:$U" "${UD}"/sentinel-*
as_u systemctl --user daemon-reload

say "3/3 dry run"
as_u python3 /usr/local/lib/sentinel/sentinel-check --dry-run
echo
echo "Enable when the dry run looks right:"
echo "  sudo -u ${U} XDG_RUNTIME_DIR=/run/user/${UID_N} systemctl --user enable --now sentinel-check.timer sentinel-digest.timer"
