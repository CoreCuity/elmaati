#!/usr/bin/env bash
# install.sh — install the fleet tool-call log + kill switch on corecuity-HQ (fleet-v1 §8, MUST #13 and #17).
#
# Run from the Mac (source of truth = this repo; never edit on the server):
#   tar -C core/elmaati/deploy/hq -czf - fleet-audit \
#     | ssh corecuity-HQ 'sudo rm -rf /root/fleet-audit && sudo tar -C /root -xzf - && sudo bash /root/fleet-audit/install.sh'
#
# What it does (idempotent):
#   1. plugin reference copy → /usr/local/lib/fleet-audit (root-owned; the watcher compares against it)
#   2. root-owned plugin copy in every Hermes home (default + profiles/*), enabled per home
#   3. fleet-audit-collector.service (journald → append-only /var/lib/fleet-audit/*.jsonl)
#   4. fleet-audit-watch.timer (every 10 min: alert if the log is off, tampered with or bypassed)
#   5. /usr/local/sbin/fleet-kill (the kill switch)
#   6. quiet gateway restart so the plugin loads, then verify
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
U=svc-hermes
H="/home/${U}"
HH="${H}/.hermes"
[ "$(id -u)" -eq 0 ] || { echo "✗ run as root" >&2; exit 1; }
UID_N="$(id -u "$U")"
as_u() { sudo -u "$U" -H env XDG_RUNTIME_DIR="/run/user/${UID_N}" HERMES_HOME="${HH}" "$@"; }
hermes() { (cd "$HH" && as_u "${HH}/hermes-agent/venv/bin/python" -m hermes_cli.main "$@"); }
say() { echo "── $* ──"; }

say "1/6 plugin reference → /usr/local/lib/fleet-audit"
install -d -m0755 /usr/local/lib/fleet-audit/plugin
rm -rf /usr/local/lib/fleet-audit/plugin/fleet-audit
cp -r "${SRC}/plugin/fleet-audit" /usr/local/lib/fleet-audit/plugin/
chown -R root:root /usr/local/lib/fleet-audit; chmod -R u=rwX,go=rX /usr/local/lib/fleet-audit

say "2/6 plugin into every Hermes home + enable"
for home in "$HH" "$HH"/profiles/*/; do
  home="${home%/}"
  name="default"; [ "$home" = "$HH" ] || name="$(basename "$home")"
  as_u mkdir -p "${home}/plugins"
  rm -rf "${home}/plugins/fleet-audit"
  cp -r /usr/local/lib/fleet-audit/plugin/fleet-audit "${home}/plugins/"
  chown -R root:root "${home}/plugins/fleet-audit"; chmod -R u=rwX,go=rX "${home}/plugins/fleet-audit"
  if [ "$name" = "default" ]; then hermes plugins enable fleet-audit; else hermes -p "$name" plugins enable fleet-audit; fi \
    | sed "s/^/   [${name}] /"
done

say "3/6 collector"
install -d -m0750 /var/lib/fleet-audit
install -m0755 "${SRC}/fleet-audit-collector" /usr/local/sbin/fleet-audit-collector
cat > /etc/systemd/system/fleet-audit-collector.service <<'EOF'
# Managed by core/elmaati/deploy/hq/fleet-audit/install.sh
[Unit]
Description=Fleet tool-call log collector (journald fleet-audit -> /var/lib/fleet-audit)
After=systemd-journald.service
[Service]
ExecStart=/usr/local/sbin/fleet-audit-collector
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF

say "4/6 watcher"
install -m0755 "${SRC}/fleet-audit-watch" /usr/local/sbin/fleet-audit-watch
cat > /etc/systemd/system/fleet-audit-watch.service <<'EOF'
# Managed by core/elmaati/deploy/hq/fleet-audit/install.sh
[Unit]
Description=Fleet tool-call log watch (alert when the log is off, tampered with or bypassed)
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/fleet-audit-watch
SuccessExitStatus=1
EOF
cat > /etc/systemd/system/fleet-audit-watch.timer <<'EOF'
# Managed by core/elmaati/deploy/hq/fleet-audit/install.sh
[Unit]
Description=Check the fleet tool-call log every 10 minutes
[Timer]
OnBootSec=5min
OnUnitActiveSec=10min
[Install]
WantedBy=timers.target
EOF

say "5/6 kill switch → /usr/local/sbin/fleet-kill"
install -m0755 "${SRC}/fleet-kill" /usr/local/sbin/fleet-kill

systemctl daemon-reload
systemctl enable --now fleet-audit-collector.service
systemctl enable --now fleet-audit-watch.timer

say "6/6 quiet gateway restart so the plugin loads"
(cd "${HH}/hermes-agent" && as_u venv/bin/python -c \
  "from gateway.drain_control import write_drain_request; write_drain_request(principal='fleet-audit-install', suppress_notification=True)")
as_u systemctl --user restart hermes-gateway.service hermes-serve.service
(cd "${HH}/hermes-agent" && as_u venv/bin/python -c \
  "from gateway.drain_control import clear_drain_request; clear_drain_request()")
sleep 20

echo; echo "verify:"
systemctl is-active fleet-audit-collector.service | sed 's/^/   collector: /' || true
ls -la /var/lib/fleet-audit/ | sed 's/^/   /'
grep -h '"audit.loaded"' /var/lib/fleet-audit/*.jsonl 2>/dev/null | tail -8 | cut -c1-200 | sed 's/^/   /'
/usr/local/sbin/fleet-audit-watch --dry-run | sed 's/^/   watch: /' || true
