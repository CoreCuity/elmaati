#!/usr/bin/env bash
# Create the `vault` tenant on corecuity-clients: Linux user, data dirs, linger, rootless Docker.
# Same pattern as the client tenants (clients/desirs/relocation/provision/01-tenant.sh).
# Idempotent. Run from the Mac:  ssh corecuity-clients 'sudo bash -s' < 01-tenant.sh
set -euo pipefail

T=vault
TUID=2011
BASE=/srv/clients/$T

if ! id "$T" >/dev/null 2>&1; then
    groupadd -g "$TUID" "$T"
    useradd -u "$TUID" -g "$TUID" -m -s /bin/bash "$T"   # no password, no SSH key: reachable only via sudo -u
fi
chmod 750 "/home/$T"

grep -q "^$T:" /etc/subuid || { echo "✗ no subuid range for $T" >&2; exit 1; }
grep -q "^$T:" /etc/subgid || { echo "✗ no subgid range for $T" >&2; exit 1; }

install -d -o "$T" -g "$T" -m 750 "$BASE"
install -d -o "$T" -g "$T" -m 750 "$BASE/app" "$BASE/backups"
install -d -o "$T" -g "$T" -m 700 "$BASE/data"

loginctl enable-linger "$T"
for _ in $(seq 1 20); do [ -S "/run/user/$TUID/bus" ] && break; sleep 1; done
[ -S "/run/user/$TUID/bus" ] || { echo "✗ user bus for $T did not come up" >&2; exit 1; }

if ! grep -q "Rootless Docker (Corecuity tenant setup)" "/home/$T/.bashrc"; then
    cat >> "/home/$T/.bashrc" <<'EOF'

# --- Rootless Docker (Corecuity tenant setup) ---
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
export PATH=/usr/bin:$PATH
EOF
fi

as_t() { sudo -u "$T" -H env XDG_RUNTIME_DIR="/run/user/$TUID" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TUID/bus" PATH=/usr/bin:/usr/sbin:/bin:/sbin "$@"; }

if [ ! -f "/home/$T/.config/systemd/user/docker.service" ]; then
    as_t dockerd-rootless-setuptool.sh install
fi
as_t systemctl --user enable --now docker.service

export DOCKER_HOST="unix:///run/user/$TUID/docker.sock"
for _ in $(seq 1 20); do as_t env DOCKER_HOST="$DOCKER_HOST" docker info >/dev/null 2>&1 && break; sleep 1; done

echo "--- result"
id "$T"
grep "^$T:" /etc/subuid
ls -ld "/home/$T" "$BASE" "$BASE"/*
ls /var/lib/systemd/linger | grep -x "$T"
as_t env DOCKER_HOST="$DOCKER_HOST" docker info --format 'docker {{.ServerVersion}} {{.Driver}} rootless={{range .SecurityOptions}}{{.}} {{end}}'
