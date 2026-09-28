#!/usr/bin/env python3
"""mk-fleet-mailbox.sh — create the fleet's own Mailcow mailbox on corecuity-clients.

Fleet v1 rule #11: the fleet acts as itself, never as a founder. This is its mail identity.
The password is NEVER an argument and is never echoed — it arrives on stdin from
.secrets/fleet-mail.env on the Mac.

    cd /Users/najlio/Projects/corecuity
    ssh corecuity-clients 'sudo install -m0700 /dev/stdin /root/mk-fleet-mailbox.sh' \
      < core/elmaati/deploy/provision/mk-fleet-mailbox.sh
    grep '^FLEET_MAIL_PASSWORD=' .secrets/fleet-mail.env | cut -d= -f2- \
      | ssh corecuity-clients 'sudo /root/mk-fleet-mailbox.sh'

Idempotent: if the mailbox exists it reports and exits 0 without touching it.
"""
import json
import subprocess
import sys
import urllib.request

MAILCOW_CONF = "/opt/mailcow/mailcow.conf"
DB_CONTAINER = "mailcowdockerized-mysql-mailcow-1"
API = "https://mail.corecuity.com/api/v1"
ADDR = "fleet@corecuity.com"


def api(path, key, payload=None):
    req = urllib.request.Request(
        f"{API}/{path}",
        data=json.dumps(payload).encode() if payload else None,
        headers={"X-API-Key": key, "Content-Type": "application/json"},
        method="POST" if payload else "GET",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read().decode()
    try:
        return r.status, json.loads(body)
    except json.JSONDecodeError:
        return r.status, body


def main():
    pw = sys.stdin.readline().strip()
    if not pw:
        sys.exit("no password on stdin")

    dbroot = ""
    for line in open(MAILCOW_CONF):
        if line.startswith("DBROOT="):
            dbroot = line.split("=", 1)[1].strip()
    if not dbroot:
        sys.exit("DBROOT not found in mailcow.conf")

    key = subprocess.run(
        ["docker", "exec", DB_CONTAINER, "mysql", "-u", "root", f"-p{dbroot}",
         "mailcow", "-N", "-B", "-e",
         "select api_key from api where access='rw' and active=1 limit 1;"],
        capture_output=True, text=True,
    ).stdout.strip()
    if not key:
        sys.exit("no active rw API key in mailcow")

    _, got = api(f"get/mailbox/{ADDR}", key)
    got = got[0] if isinstance(got, list) and got else got
    if isinstance(got, dict) and got.get("username") == ADDR:
        print(f"- {ADDR} already exists - not modified")
    else:
        status, resp = api("add/mailbox", key, {
            "local_part": "fleet", "domain": "corecuity.com",
            "name": "CoreCuity Fleet (agents)", "quota": "1024",
            "password": pw, "password2": pw,
            "active": "1", "force_pw_update": "0",
            "tls_enforce_in": "1", "tls_enforce_out": "1",
        })
        print(f"add/mailbox HTTP {status}: {json.dumps(resp)[:300]}")

    _, got = api(f"get/mailbox/{ADDR}", key)
    got = got[0] if isinstance(got, list) and got else got
    if isinstance(got, dict) and got.get("username") == ADDR:
        print(f"OK mailbox: {got['username']} | active: {got.get('active')} | "
              f"quota MB: {got.get('quota')} | domain: {got.get('domain')}")
    else:
        sys.exit("mailbox not found after create")


if __name__ == "__main__":
    main()
