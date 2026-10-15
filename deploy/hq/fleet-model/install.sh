#!/usr/bin/env bash
# install.sh — fleet-model-sync on corecuity-HQ: keeps Elmaati on a model its ChatGPT seat accepts.
# Run as root; idempotent. From the Mac (source of truth = this repo; never edit on the server):
#   COPYFILE_DISABLE=1 tar -C core/elmaati/deploy/hq -czf - fleet-model \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-model && sudo tar -C /root -xzf - \
#         && sudo bash /root/fleet-model/install.sh && sudo rm -rf /root/fleet-model'
#
#   1. /usr/local/lib/fleet-model/fleet-model-sync (root-owned; runs as svc-hermes)
#   2. svc-hermes user timer: hourly at :20, plus 07:50 and 08:50 Africa/Casablanca
#      (ten minutes before the 08:00 brief and the 09:00 ads check)
#   3. a dry run
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
U=svc-hermes
UID_N="$(id -u "$U")"
UD="/home/${U}/.config/systemd/user"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
as_u() { sudo -u "$U" XDG_RUNTIME_DIR="/run/user/${UID_N}" "$@"; }

echo "── 1/3 tool"
install -d -o root -g root -m0755 /usr/local/lib/fleet-model
install -o root -g root -m0755 "${SRC}/fleet-model-sync" /usr/local/lib/fleet-model/fleet-model-sync

echo "── 2/3 timer"
install -d -o "$U" -g "$U" -m0755 "$UD"
cat > "${UD}/fleet-model-sync.service" <<'EOF'
[Unit]
Description=Keep Elmaati on a model its ChatGPT seat accepts (core/elmaati/deploy/hq/fleet-model)

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 /usr/local/lib/fleet-model/fleet-model-sync
TimeoutStartSec=900
EOF
cat > "${UD}/fleet-model-sync.timer" <<'EOF'
[Unit]
Description=Model check: hourly, and ten minutes before the brief and the ads check

[Timer]
OnCalendar=*-*-* *:20:00
OnCalendar=*-*-* 07:50:00 Africa/Casablanca
OnCalendar=*-*-* 08:50:00 Africa/Casablanca
Persistent=true

[Install]
WantedBy=timers.target
EOF
chown "$U:$U" "${UD}/fleet-model-sync.service" "${UD}/fleet-model-sync.timer"
as_u systemctl --user daemon-reload
as_u systemctl --user enable --now fleet-model-sync.timer
as_u systemctl --user list-timers --no-pager | grep fleet-model-sync | sed 's/^/   /'

echo "── 3/3 dry run"
as_u python3 /usr/local/lib/fleet-model/fleet-model-sync --dry-run | sed "s/^/   /" || true
