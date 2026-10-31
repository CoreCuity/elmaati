#!/usr/bin/env bash
# Ship review.corecuity.com to corecuity-clients (tenant `corecuity`).
# Code + reviews/ are streamed from this checkout (commit + push first); data/ and .env stay on the server.
# Usage: deploy/clients/review/deploy.sh            (from the elmaati repo root or anywhere)
set -euo pipefail
cd "$(dirname "$0")"
test -z "$(git status --porcelain -- .)" || { echo "Commit the review/ changes first." >&2; exit 2; }
COPYFILE_DISABLE=1 tar --no-xattrs --exclude="._*" -czf - app.py review.service reviews | ssh corecuity-clients "sudo -n -u corecuity bash -c '
  set -euo pipefail
  D=/srv/clients/corecuity/review
  mkdir -p \$D/data && chmod 700 \$D/data
  tar -xzf - -C \$D 2>/dev/null
  find \$D -name "._*" -delete; chmod 750 \$D
  test -f \$D/.env || { umask 077; : > \$D/.env; }
  mkdir -p ~/.config/systemd/user && cp \$D/review.service ~/.config/systemd/user/review.service
  export XDG_RUNTIME_DIR=/run/user/\$(id -u)
  systemctl --user daemon-reload
  systemctl --user enable --now review.service >/dev/null
  systemctl --user restart review.service
  sleep 1
  curl -fsS http://127.0.0.1:8130/healthz && echo \" REVIEW_HEALTHY\"
'"
