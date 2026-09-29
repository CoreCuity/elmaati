#!/usr/bin/env python3
"""split-auth.py — one-off (2026-09-29): move basic-auth bcrypt hashes out of corecuity-clients' Caddyfile.

Runs ON the server as root. Reads /etc/caddy/Caddyfile, writes every `basicauth { … }` block as a named
snippet into /etc/caddy/auth.caddy.new (root:caddy 0640 — never committed), and prints the Caddyfile with
each block replaced by `import <snippet>` to stdout, for the repo. Refuses to print if any hash is left.
"""
import grp
import os
import re
import sys

src = open("/etc/caddy/Caddyfile").read()
block = re.compile(r"(?m)^(?P<ind>[ \t]*)basicauth \{\n(?P<body>(?:[ \t]*[^\n}]*\n)+?)[ \t]*\}\n")
NAMES = {"monitor.corecuity.com": "auth_netdata", "status.corecuity.com": "auth_netdata",
         "stage.paradisante.ma": "auth_paradisante_stage"}
by_body, snippets = {}, []


def name_for(pos, body):
    site = re.findall(r"(?m)^([a-z0-9][^\s{]*)[^\n]*\{\s*$", src[:pos])[-1]
    key = body.strip()
    if key not in by_body:
        name = NAMES.get(site, "auth_" + re.sub(r"\W", "_", site))
        by_body[key] = name
        lines = "".join("\t\t" + l.strip() + "\n" for l in key.splitlines())
        snippets.append(f"({name}) {{\n\tbasicauth {{\n{lines}\t}}\n}}\n")
    return by_body[key]


out = block.sub(lambda m: m.group("ind") + "import " + name_for(m.start(), m.group("body")) + "\n", src)
if re.search(r"\$2[aby]\$", out):
    sys.exit("a hash is left in the sanitized Caddyfile — nothing written")
path = "/etc/caddy/auth.caddy.new"
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o640)
os.write(fd, ("# Basic-auth snippets for /etc/caddy/Caddyfile. SERVER-ONLY: bcrypt hashes, never commit.\n"
              "# Referenced as `import <name>` from the repo Caddyfile (elmaati deploy/clients/caddy).\n\n"
              + "\n".join(snippets)).encode())
os.close(fd)
os.chown(path, 0, grp.getgrnam("caddy").gr_gid)
print(out, end="")
print(f"snippets written to {path}: {sorted(set(by_body.values()))}", file=sys.stderr)
