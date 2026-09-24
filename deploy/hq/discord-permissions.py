#!/usr/bin/env python3
"""discord-permissions.py — make the CoreCuity Discord's permission overrides match fleet-discord.yaml.

Least privilege for the fleet: the `Elmaati` role gets access to exactly the channels listed in
fleet-discord.yaml (and their categories); every other channel and category is closed to it. Founders see
everything through the Founder role (Administrator). Idempotent; `--dry-run` prints the plan only.

  1. every category and channel: @everyone denied View; `Elmaati` allowed where the map lists the channel;
     all other overrides removed (leftover Bot / Agent / third-party bot entries)
  2. @everyone loses Create Invite and Mention @everyone
  3. the n8n-era `Bot` and `Agent` roles are deleted (Elmaati's access no longer depends on them)
  4. invites revoked (the server is invite-by-founder only)

Needs a token with Manage Roles + Manage Channels + Manage Server (the admin bot, or Elmaati while it
temporarily holds Administrator). Usage:
  python3 discord-permissions.py <env-file-with-DISCORD_BOT_TOKEN> <fleet-discord.yaml> [--dry-run]
"""
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import yaml

ELMAATI_ROLE = "1527904926426992734"
LEFTOVER_ROLES = {"Bot", "Agent"}
VIEW = 0x400
ELMAATI_ALLOW = (0x400 | 0x800 | 0x10000 | 0x4000 | 0x8000 | 0x40   # view, send, history, embed, attach, react
                 | 0x80000000 | 0x4000000000)                      # app commands, send in threads
EVERYONE_DROP = 0x1 | 0x20000                                      # create invite, mention @everyone


def main():
    env_file, map_file = sys.argv[1], sys.argv[2]
    dry = "--dry-run" in sys.argv
    token = next(l.split("=", 1)[1].strip().strip("\"'") for l in open(env_file) if l.startswith("DISCORD_BOT_TOKEN="))
    fleet = yaml.safe_load(open(map_file))
    guild = fleet["guild_id"]
    reason = urllib.parse.quote("fleet v1 least-privilege permissions (discord-permissions.py)")
    hdr = {"Authorization": f"Bot {token}", "User-Agent": "corecuity-fleet (permissions, 1.0)",
           "Content-Type": "application/json", "X-Audit-Log-Reason": reason}

    def call(method, path, body=None):
        if dry and method != "GET":
            print(f"   DRY {method} {path} {json.dumps(body) if body else ''}")
            return {}
        while True:
            req = urllib.request.Request(f"https://discord.com/api/v10{path}", method=method, headers=hdr,
                                         data=json.dumps(body).encode() if body is not None else None)
            try:
                raw = urllib.request.urlopen(req, timeout=30).read()
                return json.loads(raw) if raw else {}
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(float(json.load(e).get("retry_after", 1)) + 0.3)
                    continue
                raise SystemExit(f"✗ {method} {path}: {e.code} {e.read().decode()[:200]}")

    chans = call("GET", f"/guilds/{guild}/channels")
    roles = call("GET", f"/guilds/{guild}/roles")
    fleet_ids = {c["id"] for c in fleet["channels"].values()}
    # A category is opened only when every channel in it is a fleet channel — otherwise a later
    # "Sync permissions" click in the UI would open the non-fleet ones.
    for cat in (c for c in chans if c["type"] == 4):
        kids = [c["id"] for c in chans if c.get("parent_id") == cat["id"]]
        if kids and all(k in fleet_ids for k in kids):
            fleet_ids.add(cat["id"])

    print("── 1/4 channel overrides")
    for c in sorted(chans, key=lambda c: (c["type"] != 4, c["position"])):
        want = {guild: (0, VIEW)}
        if c["id"] in fleet_ids:
            want[ELMAATI_ROLE] = (ELMAATI_ALLOW, 0)
        have = {o["id"]: (int(o["allow"]), int(o["deny"])) for o in c.get("permission_overwrites", [])}
        label = ("CAT " if c["type"] == 4 else "#") + c["name"]
        if have == want:
            print(f"   ok      {label}")
            continue
        print(f"   update  {label}  ({'fleet' if c['id'] in fleet_ids else 'closed to fleet'})")
        for oid, (allow, deny) in want.items():
            if have.get(oid) != (allow, deny):
                call("PUT", f"/channels/{c['id']}/permissions/{oid}", {"type": 0, "allow": str(allow), "deny": str(deny)})
        for oid in set(have) - set(want):
            call("DELETE", f"/channels/{c['id']}/permissions/{oid}")

    print("── 2/4 @everyone")
    everyone = next(r for r in roles if r["id"] == guild)
    perms = int(everyone["permissions"])
    if perms & EVERYONE_DROP:
        call("PATCH", f"/guilds/{guild}/roles/{guild}", {"permissions": str(perms & ~EVERYONE_DROP)})
        print("   removed Create Invite + Mention @everyone")
    else:
        print("   ok")

    print("── 3/4 leftover roles")
    for r in roles:
        if r["name"] in LEFTOVER_ROLES and not r["managed"]:
            call("DELETE", f"/guilds/{guild}/roles/{r['id']}")
            print(f"   deleted role {r['name']}")

    print("── 4/4 invites")
    for inv in call("GET", f"/guilds/{guild}/invites"):
        call("DELETE", f"/invites/{inv['code']}")
        print(f"   revoked {inv['code']} (#{inv['channel']['name']}, by {(inv.get('inviter') or {}).get('username')})")


if __name__ == "__main__":
    main()
