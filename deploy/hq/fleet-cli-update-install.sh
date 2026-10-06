#!/usr/bin/env bash
# fleet-cli-update-install.sh — install the weekly self-checking CLI update for svc-hermes.
#
# Run as root on corecuity-HQ, from the Mac:
#   ssh corecuity-HQ 'sudo bash -s' < deploy/hq/fleet-cli-update-install.sh
# Needs deploy/hq/fleet-cli-update.sh installed first (see its header):
#   ssh corecuity-HQ 'sudo install -o svc-hermes -g svc-hermes -m0750 /dev/stdin \
#     /home/svc-hermes/.local/bin/fleet-cli-update' < deploy/hq/fleet-cli-update.sh
#
# Installs: ~svc-hermes/.config/systemd/user/fleet-cli-update.{service,timer}
# Schedule: Sundays 05:15 (after the 04:30 gateway restart), catch-up if missed.
set -euo pipefail

U=svc-hermes
H="/home/${U}"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
UID_N="$(id -u "$U")"
as_u() { sudo -u "$U" -H env XDG_RUNTIME_DIR="/run/user/${UID_N}" \
         DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_N}/bus" \
         PATH="${H}/.local/bin:/usr/local/bin:/usr/bin:/bin" "$@"; }

[ -x "${H}/.local/bin/fleet-cli-update" ] \
  || { echo "✗ ${H}/.local/bin/fleet-cli-update missing — install deploy/hq/fleet-cli-update.sh first" >&2; exit 1; }

UD="${H}/.config/systemd/user"
as_u mkdir -p "$UD"
cat > "${UD}/fleet-cli-update.service" <<'EOF'
# Managed by core/elmaati/deploy/hq/fleet-cli-update-install.sh
[Unit]
Description=Weekly self-checking update of the fleet CLI seats (claude, codex, opencode)
[Service]
Type=oneshot
ExecStart=%h/.local/bin/fleet-cli-update
TimeoutStartSec=90min
EOF
cat > "${UD}/fleet-cli-update.timer" <<'EOF'
# Managed by core/elmaati/deploy/hq/fleet-cli-update-install.sh
[Unit]
Description=Update + verify the fleet CLI seats every Sunday 05:15
[Timer]
OnCalendar=Sun *-*-* 05:15:00
Persistent=true
RandomizedDelaySec=10min
[Install]
WantedBy=timers.target
EOF
chown "$U:$U" "${UD}"/fleet-cli-update.*
as_u systemctl --user daemon-reload
as_u systemctl --user enable --now fleet-cli-update.timer
as_u systemctl --user list-timers fleet-cli-update.timer --no-pager
