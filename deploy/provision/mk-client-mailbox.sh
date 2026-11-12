#!/usr/bin/env python3
"""mk-client-mailbox.sh — create one mailbox on Mailcow (corecuity-clients) for a client domain that is
already set up (see mk-client-mail-domain.sh). Password from stdin, never an argument, never echoed.
Idempotent: an existing mailbox is reported and left untouched (password not changed).

    ssh corecuity-clients 'sudo install -m0700 /dev/stdin /root/mk-client-mailbox.sh' \
      < core/elmaati/deploy/provision/mk-client-mailbox.sh
    grep '^MAIL_PASSWORD=' .secrets/<file>.env | cut -d= -f2- \
      | ssh corecuity-clients 'sudo /root/mk-client-mailbox.sh <address> "<display name>" [quota_mb]'

TLS is not forced in or out: a system mailbox (Odoo, a website) writes to customers whose servers may
not offer TLS, and a forced-TLS mailbox would bounce those messages.
"""
import json
import re
import subprocess
import sys
import urllib.request

DB = "mailcowdockerized-mysql-mailcow-1"
API = "https://mail.corecuity.com/api/v1"


def api_key():
    r = subprocess.run(
        ["docker", "exec", "-i", DB, "sh", "-c", 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -u root mailcow -N -B'],
        input="select api_key from api where access='rw' and active=1 limit 1;",
        capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.exit("✗ could not read the Mailcow rw API key")
    return r.stdout.strip()


def api(path, key, payload=None):
    req = urllib.request.Request(
        f"{API}/{path}",
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"X-API-Key": key, "Content-Type": "application/json"},
        method="POST" if payload is not None else "GET")
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read().decode()
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return body


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: mk-client-mailbox.sh <address> <display name> [quota_mb]")
    addr, name = sys.argv[1].lower(), sys.argv[2]
    quota = str(int(sys.argv[3])) if len(sys.argv) > 3 else "1024"
    m = re.fullmatch(r"([a-z0-9._-]+)@([a-z0-9-]+(?:\.[a-z0-9-]+)+)", addr)
    if not m:
        sys.exit("✗ address has unexpected characters")
    local, domain = m.groups()
    pw = sys.stdin.readline().strip()
    if len(pw) < 16:
        sys.exit("✗ need a password of 16+ characters on stdin")

    key = api_key()
    d = api(f"get/domain/{domain}", key)
    if not (isinstance(d, dict) and d.get("domain_name") == domain):
        sys.exit(f"✗ domain {domain} is not on Mailcow")

    got = api(f"get/mailbox/{addr}", key)
    if isinstance(got, dict) and got.get("username") == addr:
        print(f"- {addr} already exists, not modified")
    else:
        resp = api("add/mailbox", key, {
            "local_part": local, "domain": domain, "name": name, "quota": quota,
            "password": pw, "password2": pw, "active": "1", "force_pw_update": "0",
            "tls_enforce_in": "0", "tls_enforce_out": "0",
        })
        items = resp if isinstance(resp, list) else [resp]
        if not all(isinstance(i, dict) and i.get("type") == "success" for i in items):
            sys.exit(f"✗ add/mailbox: {json.dumps(resp)[:400]}")
        print(f"✓ {addr} created")

    got = api(f"get/mailbox/{addr}", key)
    d = api(f"get/domain/{domain}", key)
    print(f"OK {got.get('username')} active={got.get('active')} quota={int(got.get('quota', 0)) // 1048576} MB "
          f"imap={got.get('attributes', {}).get('imap_access')} smtp={got.get('attributes', {}).get('smtp_access')} | "
          f"{domain}: {d.get('mboxes_in_domain')}/{d.get('max_num_mboxes_for_domain')} mailboxes")


if __name__ == "__main__":
    main()
