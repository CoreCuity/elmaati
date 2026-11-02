#!/usr/bin/env bash
# deploy.sh — ship the Vaultwarden stack to tenant `vault` on corecuity-clients. Run from the Mac.
#
#   core/elmaati/deploy/clients/vault/deploy.sh
#
# Needs: 01-tenant.sh run once (ssh corecuity-clients 'sudo bash -s' < 01-tenant.sh).
# First run only: generates the admin token ON THE HOST, stores only its Argon2 hash in app/.env,
# and writes the plaintext token to the Mac at .secrets/vault-admin.env (0600) — S3, founders only.
# Never edit files on the server; change them here, commit, push, re-run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
HQ="$(cd "$HERE/../../../../.." && pwd)"          # corecuity HQ repo root
HOST="${HOST:-corecuity-clients}"
SECRET_OUT="$HQ/.secrets/vault-admin.env"
AS_VAULT='sudo -n -u vault -H env XDG_RUNTIME_DIR=/run/user/2011 DOCKER_HOST=unix:///run/user/2011/docker.sock'

echo "── 1/4 ship files"
COPYFILE_DISABLE=1 tar -C "$HERE" -czf - compose.yaml vault-backup.sh vault-backup.service vault-backup.timer \
  | ssh "$HOST" "$AS_VAULT tar -C /srv/clients/vault/app -xzf - && $AS_VAULT chmod 750 /srv/clients/vault/app/vault-backup.sh" 2>&1 | grep -v LIBARCHIVE || true

echo "── 2/4 admin token (first run only)"
if ssh "$HOST" "$AS_VAULT test -s /srv/clients/vault/app/.env"; then
  echo "   .env exists — token left as is"
else
  [ -e "$SECRET_OUT" ] && { echo "✗ $SECRET_OUT exists but the server has no .env — resolve by hand"; exit 1; }
  umask 077
  # Plaintext goes straight into the Mac file; the server keeps only the hash.
  ssh "$HOST" "$AS_VAULT bash -s" > "$SECRET_OUT" <<'REMOTE'
set -euo pipefail
umask 077
TOKEN=$(openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-48)
# `vaultwarden hash` reads the password from a terminal only, so `script` provides one.
HASH=$(printf '%s\n%s\n' "$TOKEN" "$TOKEN" \
       | script -qec "docker run -it --rm vaultwarden/server:1.37.4 /vaultwarden hash --preset owasp" /dev/null 2>/dev/null \
       | tr -d '\r' | grep -o "\$argon2id\$[^'\" ]*" | head -1)
[ -n "$HASH" ] || { echo "HASH_FAILED" >&2; exit 1; }
# Compose env files treat $ as interpolation: double them.
printf "ADMIN_TOKEN='%s'\n" "${HASH//\$/\$\$}" > /srv/clients/vault/app/.env
chmod 600 /srv/clients/vault/app/.env
printf 'VAULT_ADMIN_URL=https://vault.corecuity.com/admin\nVAULT_ADMIN_TOKEN=%s\n' "$TOKEN"
REMOTE
  chmod 600 "$SECRET_OUT"
  grep -q '^VAULT_ADMIN_TOKEN=.\{40,\}' "$SECRET_OUT" || { echo "✗ token not captured"; rm -f "$SECRET_OUT"; exit 1; }
  echo "   ✓ token generated; plaintext in .secrets/vault-admin.env (Mac), hash on the server"
fi

echo "── 3/4 start"
ssh "$HOST" "$AS_VAULT docker compose --project-directory /srv/clients/vault/app -f /srv/clients/vault/app/compose.yaml up -d --remove-orphans 2>&1 | tail -3"
for _ in $(seq 1 30); do
  ssh "$HOST" "curl -fsS -o /dev/null http://127.0.0.1:8114/alive" 2>/dev/null && break; sleep 2
done
ssh "$HOST" "curl -fsS -o /dev/null -w '   /alive %{http_code}\n' http://127.0.0.1:8114/alive"

echo "── 4/4 backup timer"
ssh "$HOST" "$AS_VAULT bash -c 'mkdir -p ~/.config/systemd/user && cp /srv/clients/vault/app/vault-backup.{service,timer} ~/.config/systemd/user/ \
  && XDG_RUNTIME_DIR=/run/user/2011 systemctl --user daemon-reload \
  && XDG_RUNTIME_DIR=/run/user/2011 systemctl --user enable --now vault-backup.timer >/dev/null \
  && XDG_RUNTIME_DIR=/run/user/2011 systemctl --user list-timers vault-backup.timer --no-pager | sed -n 2p'"
echo "✓ done"
