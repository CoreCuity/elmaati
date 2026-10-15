#!/usr/bin/env bash
# Run ON corecuity-clients from a clean, pulled checkout, after backend readiness.
# sudo ./install-from-checkout.sh <full-commit> <current-live-caddyfile-sha256>
# No source edits; only installs the reviewed runtime config and keeps its backup.
set -euo pipefail
[ "$#" -eq 2 ] || { echo "Usage: $0 <full-commit> <live-config-sha256>" >&2; exit 2; }
[ "$(id -u)" -eq 0 ] || { echo 'Run with sudo.' >&2; exit 2; }
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel)"
EXPECTED_COMMIT="$1"
EXPECTED_LIVE_HASH="$2"
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ && "$EXPECTED_LIVE_HASH" =~ ^[0-9a-f]{64}$ ]] || exit 2
[ "$(git -C "$REPO" rev-parse HEAD)" = "$EXPECTED_COMMIT" ] || { echo 'Checkout commit differs.' >&2; exit 1; }
[ -z "$(git -C "$REPO" status --porcelain --untracked-files=all)" ] || { echo 'Checkout is dirty.' >&2; exit 1; }
LIVE=/etc/caddy/Caddyfile
[ "$(sha256sum "$LIVE" | cut -d' ' -f1)" = "$EXPECTED_LIVE_HASH" ] || { echo 'Live config changed; review drift before installing.' >&2; exit 1; }
test -f /etc/caddy/auth.caddy
systemctl is-active --quiet caddy
CANDIDATE="$(mktemp /etc/caddy/Caddyfile.candidate.XXXXXX)"
trap 'rm -f "$CANDIDATE"' EXIT
install -o root -g caddy -m0640 "$HERE/Caddyfile" "$CANDIDATE"
caddy validate --adapter caddyfile --config "$CANDIDATE"
# Recheck after validation so concurrent route changes cannot be silently overwritten.
[ "$(sha256sum "$LIVE" | cut -d' ' -f1)" = "$EXPECTED_LIVE_HASH" ] || { echo 'Live config changed during validation.' >&2; exit 1; }
BACKUP="$LIVE.bak-$(date -u +%Y%m%d-%H%M%S)-${EXPECTED_COMMIT:0:12}"
test ! -e "$BACKUP"
cp -p "$LIVE" "$BACKUP"
install -o root -g caddy -m0640 "$CANDIDATE" "$LIVE"
if ! systemctl reload caddy || ! systemctl is-active --quiet caddy; then
    echo "Reload failed; restoring $BACKUP" >&2
    cp -p "$BACKUP" "$LIVE"
    systemctl reload caddy
    systemctl is-active --quiet caddy
    exit 1
fi
printf 'Installed commit %s; backup %s\n' "$EXPECTED_COMMIT" "$BACKUP"
sha256sum "$LIVE"
