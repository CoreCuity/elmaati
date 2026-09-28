"""mk-fleet-plane-user.py — create the fleet's own Plane account via Plane's Django models.

Runs INSIDE the plane-app-api container. Reads the password from /tmp/.fleet-pw (docker-cp'd in,
shredded by the caller) so it never appears in a command line or the process list.

Creates, idempotently:
  - User fleet@corecuity.com (active, password set)
  - WorkspaceMember in the 'workspace' workspace with role 15 = Member (never 20 = Admin)
  - marks the pending WorkspaceMemberInvite accepted
  - an APIToken labelled 'fleet-agent'

Writes the API token to /tmp/.fleet-token for the caller to collect. Prints no secret.

Fleet v1 rule #11: the fleet acts as itself, never as a founder.
Source of truth: elmaati repo, deploy/provision/ (core/elmaati/deploy/provision/ on the Mac). Never edit on a server.
"""
import os
import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "plane.settings.production")
django.setup()

from plane.db.models import (  # noqa: E402
    APIToken, User, Workspace, WorkspaceMember, WorkspaceMemberInvite,
)

EMAIL = "fleet@corecuity.com"
SLUG = "workspace"
ROLE_MEMBER = 15

with open("/tmp/.fleet-pw") as fh:
    password = fh.readline().strip()
if not password:
    raise SystemExit("no password provided")

ws = Workspace.objects.get(slug=SLUG)

user = User.objects.filter(email=EMAIL).first()
if user:
    print("- user already exists")
else:
    user = User(
        email=EMAIL,
        username=EMAIL,
        display_name="CoreCuity Fleet",
        first_name="CoreCuity",
        last_name="Fleet",
        is_active=True,
        is_superuser=False,
    )
    user.set_password(password)
    user.is_password_autoset = False
    user.save()
    print("+ user created")

member, created = WorkspaceMember.objects.get_or_create(
    workspace=ws, member=user, defaults={"role": ROLE_MEMBER, "is_active": True}
)
if not created:
    # never silently escalate an existing membership
    print(f"- membership already present (role {member.role})")
else:
    print(f"+ workspace member created (role {member.role})")

inv = WorkspaceMemberInvite.objects.filter(email=EMAIL, workspace=ws).first()
if inv and not inv.accepted:
    inv.accepted = True
    inv.save()
    print("+ invite marked accepted")

tok = APIToken.objects.filter(user=user, workspace=ws, label="fleet-agent").first()
if tok:
    print("- API token 'fleet-agent' already exists; not regenerating")
    value = None
else:
    tok = APIToken.objects.create(
        user=user, workspace=ws, label="fleet-agent",
        description="Fleet v1 agent identity (rule #11). Created 2026-09-20.",
        is_active=True,
    )
    value = tok.token
    print("+ API token created")

if value:
    with open("/tmp/.fleet-token", "w") as fh:
        fh.write(value)

print(f"= user={user.email} active={user.is_active} superuser={user.is_superuser} "
      f"role={member.role} workspace={ws.slug}")
