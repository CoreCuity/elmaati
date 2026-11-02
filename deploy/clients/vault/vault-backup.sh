#!/usr/bin/env bash
# Nightly Vaultwarden backup, run as tenant `vault` by vault-backup.timer (user unit).
# Consistent SQLite copy via `vaultwarden backup`, plus the files the DB does not hold
# (rsa keys = login tokens, attachments, sends, config.json). Keeps 14 days.
# Everything stays end-to-end encrypted: entries are ciphertext without a user's master password.
# Off-site copy: Storage Box sub-account backups/clients/vault (not wired yet — plan §3.1).
set -euo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)" DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"

BASE=/srv/clients/vault
DATA=$BASE/data
OUT=$BASE/backups
TS=$(date +%Y%m%d-%H%M%S)
KEEP_DAYS=14

docker exec vaultwarden /vaultwarden backup >/dev/null
DB=$(ls -t "$DATA"/db_*.sqlite3 | head -1)        # written by the line above
[ -s "$DB" ] || { echo "✗ backup produced no database file" >&2; exit 1; }

umask 077
tar -C "$DATA" -czf "$OUT/vault-$TS.tgz" \
    --transform "s|^$(basename "$DB")|db.sqlite3|" \
    "$(basename "$DB")" \
    $(cd "$DATA" && ls -d rsa_key* attachments sends config.json 2>/dev/null)
rm -f "$DB"

tar -tzf "$OUT/vault-$TS.tgz" | grep -qx db.sqlite3 || { echo "✗ archive has no db.sqlite3" >&2; exit 1; }
find "$OUT" -name 'vault-*.tgz' -mtime +"$KEEP_DAYS" -delete
echo "✓ $OUT/vault-$TS.tgz ($(du -h "$OUT/vault-$TS.tgz" | cut -f1))"
