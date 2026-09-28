#!/usr/bin/env bash
# new-agent.sh — the per-agent isolation primitive for corecuity-HQ (roadmap Phase 2).
#
# Creates (idempotently) one service identity per agent:
#   svc-<name> user, own group, own subuid/subgid range, nologin shell
#   home /home/svc-<name> mode 0750  (under /home so the nightly `hq` restic set covers it)
#   enable-linger (its user systemd manager survives logout + boots)
#   CPUQuota / MemoryMax / TasksMax on its user slice (the cap the miner never hit)
#   asserts: not in sudo / docker / adm / systemd-journal
#
# Source of truth: elmaati repo, deploy/provision/new-agent.sh. Never edit on the server.
# Run from the Mac:  ssh corecuity-HQ 'sudo bash -s -- hermes 150% 2G' < core/elmaati/deploy/provision/new-agent.sh
#
# Deliberately NOT here yet (add when an agent needs it): rootless dockerd, Caddy vhost,
# port registry, per-agent backup unit.
set -euo pipefail

NAME="${1:?usage: new-agent.sh <name> [cpu-quota e.g. 150%] [memory-max e.g. 2G]}"
CPU="${2:-100%}"
MEM="${3:-1G}"
TASKS="${TASKS:-512}"
USER_NAME="svc-${NAME}"
HOME_DIR="/home/${USER_NAME}"

[ "$(id -u)" -eq 0 ] || { echo "✗ run as root (sudo)" >&2; exit 1; }
[[ "$NAME" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo "✗ bad name: $NAME" >&2; exit 1; }

if id "$USER_NAME" >/dev/null 2>&1; then
  echo "• user $USER_NAME exists — reconciling"
else
  # Regular (non-system) uid so useradd allocates a subuid/subgid range for future rootless docker.
  useradd --create-home --home-dir "$HOME_DIR" --shell /usr/sbin/nologin --user-group \
          --comment "CoreCuity agent ${NAME}" "$USER_NAME"
  echo "✓ created $USER_NAME"
fi

UID_N="$(id -u "$USER_NAME")"
chmod 0750 "$HOME_DIR"
chown "$USER_NAME:$USER_NAME" "$HOME_DIR"
usermod --shell /usr/sbin/nologin "$USER_NAME"
passwd --lock "$USER_NAME" >/dev/null 2>&1 || true

grep -q "^${USER_NAME}:" /etc/subuid || { echo "✗ no subuid range for $USER_NAME" >&2; exit 1; }

loginctl enable-linger "$USER_NAME"

SLICE_DIR="/etc/systemd/system/user-${UID_N}.slice.d"
mkdir -p "$SLICE_DIR"
cat > "${SLICE_DIR}/50-corecuity-limits.conf" <<EOF
# Managed by core/elmaati/deploy/provision/new-agent.sh — agent ${NAME}
[Slice]
CPUQuota=${CPU}
MemoryMax=${MEM}
TasksMax=${TASKS}
EOF
systemctl daemon-reload

# Wait for the user manager (linger starts it) so callers can use systemctl --user right away.
for _ in $(seq 1 20); do [ -S "/run/user/${UID_N}/bus" ] && break; sleep 0.5; done

# Assertions — fail loudly rather than silently leave a privileged agent.
for g in sudo docker adm systemd-journal lxd; do
  if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qx "$g"; then
    echo "✗ $USER_NAME is in group $g — refusing" >&2; exit 1
  fi
done
[ -f "/etc/sudoers.d/${USER_NAME}" ] && { echo "✗ sudoers entry exists for $USER_NAME" >&2; exit 1; }

echo "✓ ${USER_NAME} uid=${UID_N} home=${HOME_DIR} (0750) linger=on"
echo "  slice: $(systemctl show "user-${UID_N}.slice" -p CPUQuotaPerSecUSec -p MemoryMax -p TasksMax | tr '\n' ' ')"
echo "  user bus: $( [ -S /run/user/${UID_N}/bus ] && echo up || echo 'not yet' )"
