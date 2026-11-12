#!/usr/bin/env python3
"""mk-client-mail-domain.sh — put a client's domain on Mailcow (corecuity-clients) and give the
client a domain administrator, so they create and manage their own mailboxes inside limits we set.

What it does, idempotently (anything that already exists is reported and left alone):
  1. Backs up the Mailcow tables it touches to /root/backups/ (gzip-verified).
  2. Adds the domain with mailbox / storage / sending-rate limits, and a 2048-bit DKIM key (selector "dkim").
  3. Adds postmaster@ and abuse@ as aliases to admin@corecuity.com.
  4. Adds the domain administrator (password from stdin, never an argument, never echoed).
  5. Sets what that administrator may do (ACL below). Re-applied on every run.
  6. Restarts SOGo when the domain is new: SOGo builds its per-domain login config only at start,
     so webmail answers 403 for a new domain until it restarts (hq-ops drawer 2026-08-05).
  7. Prints the DNS records to publish (public values only).

Usage, from the HQ root on the Mac:
    ssh corecuity-clients 'sudo install -m0700 /dev/stdin /root/mk-client-mail-domain.sh' \
      < core/elmaati/deploy/provision/mk-client-mail-domain.sh
    grep '^MAIL_ADMIN_PASSWORD=' .secrets/<client>-mail-admin.env | cut -d= -f2- \
      | ssh corecuity-clients 'sudo /root/mk-client-mail-domain.sh <domain> <admin-username> "<description>"'

Limits (override with env on the remote side): MAILBOXES=10 QUOTA_MB=10240 DEFQUOTA_MB=1024
MAXQUOTA_MB=5120 ALIASES=100 RL_VALUE=300 RL_FRAME=h (outgoing messages per hour, whole domain).
"""
import datetime
import gzip
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

DB ="mailcowdockerized-mysql-mailcow-1"
SOGO = "mailcowdockerized-sogo-mailcow-1"
API = "https://mail.corecuity.com/api/v1"
POSTMASTER_GOTO = "admin@corecuity.com"

# What the client's administrator may do. Everything not listed is off:
#   bcc_maps (silent copy of all mail), pushover, ratelimit, extend_sender_acl (send as other domains),
#   unlimited_quota, smtp_ip_access, alias_domains (claim other domains), mailbox_relayhost,
#   domain_relayhost, domain_desc.
DA_ACL = [
    "syncjobs",            # import old mail from another server (IMAP)
    "quarantine",          # see and release quarantined mail
    "login_as",            # open a staff mailbox to help someone
    "sogo_access",         # webmail
    "app_passwds",         # app passwords for phones
    "filters",             # mail filters
    "spam_policy",         # allow / block lists
    "protocol_access",     # turn IMAP / POP3 / SMTP on or off per mailbox
    "alias_external_goto", # forward an address to an outside inbox (e.g. a Gmail)
]


def env_int(name, default):
    return str(int(os.environ.get(name, default)))


def in_db(cmd, stdin=None, text=True):
    """Run a mysql/mysqldump command inside the DB container with the container's own root password
    (MYSQL_ROOT_PASSWORD), so the password never appears in a process list or in an error message."""
    r = subprocess.run(["docker", "exec", "-i", DB, "sh", "-c", f'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" {cmd}'],
                       input=stdin, capture_output=True, text=text)
    if r.returncode != 0:
        err = r.stderr if text else r.stderr.decode(errors="replace")
        sys.exit(f"✗ database command failed ({cmd.split()[0]}): {err.strip()[:300]}")
    return r.stdout


def sql(query):
    return in_db("mysql -u root mailcow -N -B", stdin=query).strip()


def api(path, key, payload=None):
    req = urllib.request.Request(
        f"{API}/{path}",
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"X-API-Key": key, "Content-Type": "application/json"},
        method="POST" if payload is not None else "GET",
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        body = r.read().decode()
    try:
        return json.loads(body)
    except json.JSONDecodeError:
        return body


def ok(resp, what):
    items = resp if isinstance(resp, list) else [resp]
    bad = [i for i in items if not (isinstance(i, dict) and i.get("type") == "success")]
    if bad:
        sys.exit(f"✗ {what}: {json.dumps(resp)[:400]}")
    print(f"✓ {what}")


def backup(domain):
    # DKIM keys live in Redis, not MySQL; a new domain gets a new key, so nothing there to back up.
    os.makedirs("/root/backups", mode=0o700, exist_ok=True)
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d-%H%M%S")
    path = f"/root/backups/mailcow-pre-{domain}-{ts}.sql.gz"
    dump = in_db("mysqldump -u root --single-transaction mailcow "
                 "domain domain_admins da_acl admin alias mailbox", text=False)
    if len(dump) < 1000:
        sys.exit("✗ backup looks empty, stopping")
    with gzip.open(path, "wb") as f:
        f.write(dump)
    os.chmod(path, 0o600)
    with gzip.open(path, "rb") as f:
        f.read()
    print(f"✓ backup {path} ({os.path.getsize(path)} bytes, gzip OK)")


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: mk-client-mail-domain.sh <domain> <admin-username> [description]")
    domain, admin = sys.argv[1].lower(), sys.argv[2]
    if not re.fullmatch(r"[a-z0-9-]+(\.[a-z0-9-]+)+", domain) or not re.fullmatch(r"[A-Za-z0-9._-]{3,64}", admin):
        sys.exit("✗ domain or admin username has unexpected characters")
    desc = sys.argv[3] if len(sys.argv) > 3 else domain
    pw = sys.stdin.readline().strip()
    if len(pw) < 16:
        sys.exit("✗ need a password of 16+ characters on stdin")

    key = sql("select api_key from api where access='rw' and active=1 limit 1;")
    if not key:
        sys.exit("✗ no active rw API key in mailcow")

    backup(domain)

    # 1. Domain
    new_domain = False
    got = api(f"get/domain/{domain}", key)
    if isinstance(got, dict) and got.get("domain_name") == domain:
        print(f"- domain {domain} already exists, limits not changed")
    else:
        ok(api("add/domain", key, {
            "domain": domain, "description": desc, "active": "1",
            "mailboxes": env_int("MAILBOXES", 10), "aliases": env_int("ALIASES", 100),
            "quota": env_int("QUOTA_MB", 10240), "defquota": env_int("DEFQUOTA_MB", 1024),
            "maxquota": env_int("MAXQUOTA_MB", 5120),
            "rl_value": env_int("RL_VALUE", 300), "rl_frame": os.environ.get("RL_FRAME", "h"),
            "backupmx": "0", "relay_all_recipients": "0", "relay_unknown_only": "0", "gal": "1",
            "dkim_selector": "dkim", "key_size": "2048", "restart_sogo": "0",
        }), f"domain {domain} added")
        new_domain = True

    # 2. DKIM (add/domain normally creates it; add/dkim on an existing key is rejected, so check first)
    dkim = api(f"get/dkim/{domain}", key)
    if not (isinstance(dkim, dict) and dkim.get("dkim_txt")):
        ok(api("add/dkim", key, {"domains": domain, "dkim_selector": "dkim", "key_size": 2048}), "DKIM key added")
        dkim = api(f"get/dkim/{domain}", key)

    # 3. postmaster@ / abuse@
    aliases = api("get/alias/all", key)
    have = {a.get("address") for a in aliases} if isinstance(aliases, list) else set()
    for local in ("postmaster", "abuse"):
        addr = f"{local}@{domain}"
        if addr in have:
            print(f"- alias {addr} already exists")
        else:
            ok(api("add/alias", key, {"address": addr, "goto": POSTMASTER_GOTO, "active": "1"}),
               f"alias {addr} → {POSTMASTER_GOTO}")

    # 4. Domain administrator
    admins = api("get/domain-admin/all", key)
    existing = next((a for a in admins if a.get("username") == admin), None) if isinstance(admins, list) else None
    if existing:
        print(f"- domain admin {admin} already exists, password not changed")
    else:
        ok(api("add/domain-admin", key, {
            "username": admin, "domains": domain, "password": pw, "password2": pw, "active": "1",
        }), f"domain admin {admin} for {domain}")

    # 5. What the administrator may do
    ok(api("edit/da-acl", key, {"items": [admin], "attr": {"da_acl": DA_ACL}}), "domain admin rights set")

    # 6. SOGo
    if new_domain:
        subprocess.run(["docker", "restart", SOGO], check=True, capture_output=True)
        for _ in range(30):
            time.sleep(3)
            st = subprocess.run(["docker", "inspect", "-f", "{{.State.Running}}", SOGO],
                                capture_output=True, text=True).stdout.strip()
            if st == "true":
                break
        print(f"✓ SOGo restarted (running={st})")

    # Check
    d = api(f"get/domain/{domain}", key)
    a = next((x for x in api("get/domain-admin/all", key) if x.get("username") == admin), {})
    acl = sql(f"select * from da_acl where username='{admin}'\\G").replace("\n", " ")
    print(f"OK domain {d.get('domain_name')} active={d.get('active')} mailboxes max={d.get('max_num_mboxes_for_domain')} "
          f"quota={int(d.get('max_quota_for_domain', 0)) // 1048576} MB | admin {a.get('username')} "
          f"active={a.get('active')} domains={a.get('selected_domains')}")
    print(f"ACL: {acl}")

    # 7. DNS to publish
    print("DNS_JSON " + json.dumps({
        "MX": "mail.corecuity.com",
        "SPF": "v=spf1 mx -all",
        "DKIM_NAME": f"{dkim.get('dkim_selector', 'dkim')}._domainkey",
        "DKIM_TXT": dkim.get("dkim_txt"),
    }))


if __name__ == "__main__":
    main()
