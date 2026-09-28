"""rotate-plane-token.py — replace one Plane API token with a fresh one via Plane's Django models.

Runs INSIDE the plane-app-api container (same method as mk-fleet-plane-user.py). The caller docker-cp's
the OLD token into /tmp/.old-token; this script finds that exact token, creates a new token for the same
user and workspace (label suffixed with the rotation date), then DEACTIVATES the old one (is_active=False,
kept for audit — delete it later from the UI). The new token is written to /tmp/.new-token for the caller
to collect and shred. Prints no secret.

    docker exec -e PYTHONPATH=/code -w /code plane-app-api-1 python /tmp/rotate.py

Source of truth: elmaati repo, deploy/provision/ (core/elmaati/deploy/provision/ on the Mac). Never edit on a server.
"""
import datetime
import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "plane.settings.production")
django.setup()

from plane.db.models import APIToken  # noqa: E402

with open("/tmp/.old-token") as fh:
    old_value = fh.readline().strip()
if not old_value:
    raise SystemExit("no old token provided")

old = APIToken.objects.filter(token=old_value).first()
if not old:
    raise SystemExit("old token not found — nothing changed")
if not old.is_active:
    raise SystemExit("old token is already inactive — nothing changed")

today = datetime.date.today().isoformat()
new = APIToken.objects.create(
    user=old.user, workspace=old.workspace,
    label=f"{old.label or 'api'} (rotated {today})"[:255],
    description=f"Rotated {today}: the previous token's value was exposed (secrets audit).",
    is_active=True,
)
old.is_active = False
old.save(update_fields=["is_active"])

fd = os.open("/tmp/.new-token", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, (new.token + "\n").encode())
os.close(fd)
print(f"user={old.user.email} workspace={getattr(old.workspace, 'slug', None)} "
      f"old_label={old.label!r} -> deactivated; new token created (label {new.label!r})")
