#!/usr/bin/env bash
# upgrade-caddy.sh — move corecuity-clients from Ubuntu's Caddy 2.6.2 to the official Caddy apt repo.
# Runs ON the host as root, fed over ssh from the Mac (never copy it to the server):
#
#   ssh corecuity-clients 'sudo bash -s -- prepare' < upgrade-caddy.sh   # add repo, fetch, validate. Changes no running service.
#   ssh corecuity-clients 'sudo bash -s -- install' < upgrade-caddy.sh   # back up, install, restart, verify.
#
# `prepare` proves the LIVE /etc/caddy/Caddyfile validates on the exact binary `install` will put in place.
# Roll back: apt-get install -y --allow-downgrades caddy=<old version printed by install>
#            (the Caddyfile is never touched here; /etc/caddy is copied to /root/caddy-pre-upgrade-<ts>/ first).
set -euo pipefail
# The script itself arrives on stdin (bash -s): every command that might read stdin gets < /dev/null.
MODE="${1:?prepare|install}"
export DEBIAN_FRONTEND=noninteractive
KEYRING=/usr/share/keyrings/caddy-stable-archive-keyring.gpg
LIST=/etc/apt/sources.list.d/caddy-stable.list
STAGE=/root/caddy-upgrade-stage

prepare() {
    if [ ! -s "$KEYRING" ]; then
        k=$(mktemp)
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' -o "$k" < /dev/null
        grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$k" || { echo "✗ could not fetch the Caddy repo key" >&2; rm -f "$k"; exit 1; }
        gpg --batch --no-tty --yes --dearmor -o "$KEYRING" < "$k"
        rm -f "$k"; chmod 0644 "$KEYRING"
    fi
    if [ ! -s "$LIST" ]; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' < /dev/null > "$LIST"
        chmod 0644 "$LIST"
    fi
    apt-get update -qq -o Dir::Etc::sourcelist="$LIST" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" < /dev/null
    echo "installed : $(dpkg-query -W -f='${Version}' caddy)"
    echo "candidate : $(apt-cache policy caddy | awk '/Candidate:/{print $2}')"
    rm -rf "$STAGE"; mkdir -p "$STAGE"; chmod 700 "$STAGE"; cd "$STAGE"
    chown _apt "$STAGE" 2>/dev/null || true
    apt-get download caddy < /dev/null >/dev/null
    chown root "$STAGE"
    dpkg-deb -x caddy_*.deb x
    echo "new binary: $("$STAGE/x/usr/bin/caddy" version)"
    echo "--- unit shipped by the new package vs the one running"
    diff <(grep -vE '^\s*(#|;|$)' /usr/lib/systemd/system/caddy.service) <(grep -vE '^\s*(#|;|$)' "$STAGE/x/usr/lib/systemd/system/caddy.service" 2>/dev/null || grep -vE '^\s*(#|;|$)' "$STAGE/x/lib/systemd/system/caddy.service") || true
    echo "--- live Caddyfile on the new binary"
    "$STAGE/x/usr/bin/caddy" validate --adapter caddyfile --config /etc/caddy/Caddyfile 2>&1 | tail -3
}

install_() {
    [ -x "$STAGE/x/usr/bin/caddy" ] || { echo "✗ run prepare first" >&2; exit 1; }
    "$STAGE/x/usr/bin/caddy" validate --adapter caddyfile --config /etc/caddy/Caddyfile >/dev/null 2>&1 \
        || { echo "✗ live Caddyfile does not validate on the new binary — not installing" >&2; exit 1; }
    ts=$(date +%Y%m%d-%H%M%S); bk=/root/caddy-pre-upgrade-$ts
    old=$(dpkg-query -W -f='${Version}' caddy)
    mkdir -p "$bk"; chmod 700 "$bk"
    cp -a /etc/caddy "$bk/etc-caddy"
    cp -a /usr/bin/caddy "$bk/caddy-$old"
    cp -a /var/lib/caddy "$bk/var-lib-caddy"
    echo "backup    : $bk (old version $old)"
    # confold: keep our /etc/caddy/Caddyfile, never the package's sample.
    apt-get install -y -qq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold caddy < /dev/null >/dev/null
    systemctl daemon-reload
    systemctl is-active --quiet caddy || systemctl restart caddy
    sleep 3
    echo "now       : $(caddy version)"
    echo "service   : $(systemctl is-active caddy) since $(systemctl show caddy -p ActiveEnterTimestamp --value)"
    echo "run as    : $(ps -o user= -C caddy | sort -u | tr '\n' ' ')"
    cmp -s "$bk/etc-caddy/Caddyfile" /etc/caddy/Caddyfile && echo "Caddyfile : unchanged" || echo "✗ Caddyfile CHANGED by the package"
    journalctl -u caddy --since "-2min" -p warning --no-pager | tail -8
}

case "$MODE" in
    prepare) prepare ;;
    install) install_ ;;
    *) echo "usage: prepare|install" >&2; exit 2 ;;
esac
