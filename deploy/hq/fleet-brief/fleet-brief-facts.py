#!/usr/bin/env python3
"""fleet-brief-facts — the facts behind Elmaati's 08:00 brief (fleet-v1 §3, §10 phase 1).

Hermes cron runs this before the agent (`hermes cron create --script`); its stdout is the
only material the brief is written from. Deterministic: the model phrases, it does not fetch.

Sources, all read-only and all already the fleet's:
  Sentinel  python3 /usr/local/lib/sentinel/sentinel-check --digest --dry-run
  Plane     /usr/local/bin/fleet-plane (6 projects, GET only)
  Vault     /var/lib/fleet-vault (founder-approved cards/timelines + the fleet's journal)

Installed root-owned by core/elmaati/deploy/hq/fleet-brief/install.sh. Never edit on the box.
"""
from __future__ import annotations

import datetime as dt
import json
import re
import subprocess
import time
from pathlib import Path
from zoneinfo import ZoneInfo

TZ = ZoneInfo("Africa/Casablanca")
CLIENTS = [("ADOL", "adolia", "Adolia"), ("ODAE", "odae", "Odae"), ("DD", "desirs", "Désirs d'Orient")]
INTERNAL = [("AHQ", "Core Agents HQ (the fleet)"), ("CORE", "CoreCuity"), ("OPS", "Agency Ops")]
VAULT = Path("/var/lib/fleet-vault")
SHADOW_FIRST, SHADOW_DAYS = dt.date(2026, 10, 3), 5
STALE_DAYS = 14
LONG_OVERDUE_DAYS = 30

now = dt.datetime.now(TZ)
today = now.date()
since = today - dt.timedelta(days=1)


def run(cmd: list[str], timeout: int = 120) -> tuple[int, str]:
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, ""


def plane(*args: str) -> dict:
    code, out = run(["/usr/local/bin/fleet-plane", *args])
    try:
        return json.loads(out)
    except ValueError:
        return {"ok": False, "error": f"no answer (exit {code})"}


def line(i: dict) -> str:
    bits = [i["state"]]
    if i.get("assignees"):
        bits.append("→ " + ", ".join(i["assignees"]))
    if i.get("due"):
        bits.append(f"due {i['due']}")
    bits.append(f"updated {i['updated'][:10]}")
    return f"- {i['key']} {i['name']} ({'; '.join(bits)})"


def plane_facts(key: str, changed: list[dict]) -> list[str]:
    r = plane("issues", key, "--limit=150")
    if not r.get("ok"):
        return [f"Plane {key}: UNAVAILABLE — {r.get('error')}"]
    open_ = r["issues"]
    out = [f"Plane {key}: {len(open_)}{'+' if len(open_) >= 150 else ''} open work items."]
    blocked = [i for i in open_ if "block" in i["state"].lower()]
    out.append(f"Blocked ({len(blocked)}):" if blocked else "Blocked: none.")
    out += [line(i) for i in blocked]
    week = (today + dt.timedelta(days=7)).isoformat()
    month_ago = (today - dt.timedelta(days=LONG_OVERDUE_DAYS)).isoformat()
    due = sorted((i for i in open_ if i.get("due") and month_ago <= i["due"] <= week), key=lambda i: i["due"])
    out.append(f"Overdue (last {LONG_OVERDUE_DAYS} days) or due within 7 days ({len(due)}):" if due
               else f"Overdue (last {LONG_OVERDUE_DAYS} days) or due within 7 days: none.")
    out += [line(i) + (" OVERDUE" if i["due"] < today.isoformat() else "") for i in due]
    old = sorted((i for i in open_ if i.get("due") and i["due"] < month_ago), key=lambda i: i["due"])
    if old:
        out.append(f"Long overdue (due before {month_ago}): {len(old)} items, oldest due {old[0]['due']} — "
                   + ", ".join(i["key"] for i in old[:12]) + (" …" if len(old) > 12 else ""))
    cut = (today - dt.timedelta(days=STALE_DAYS)).isoformat()
    stale = sorted((i for i in open_ if i["updated"][:10] < cut and i["state_group"] == "started"),
                   key=lambda i: i["updated"])
    out.append(f"In progress but untouched for {STALE_DAYS}+ days ({len(stale)}), oldest first:" if stale
               else f"In progress but untouched for {STALE_DAYS}+ days: none.")
    out += [line(i) for i in stale[:5]]
    out.append(f"Changed since {since.isoformat()} ({len(changed)}):" if changed else f"Changed since {since.isoformat()}: nothing.")
    out += [line(i) for i in changed[:10]]
    return out


def vault_facts(folder: str) -> list[str]:
    out = []
    tl = VAULT / "clients" / folder / "timeline.md"
    if tl.exists():
        waiting = [l.strip() for l in tl.read_text().splitlines() if "· waiting ·" in l]
        if waiting:
            out.append("Vault timeline, waiting items (founder-approved, may be dated):")
            out += waiting[:5]
    jdir = VAULT / "clients" / folder / "journal"
    entries = []
    for f in sorted(jdir.glob("*.md"))[-2:] if jdir.exists() else []:
        for m in re.finditer(r"^## (\d{4}-\d{2}-\d{2}) [\d:]+ · (\w+)\n\n(.+?)\n", f.read_text(), re.M):
            if m.group(1) >= since.isoformat():
                entries.append(f"- {m.group(1)} · {m.group(2)} · {m.group(3)}")
    out.append(f"Fleet journal since {since.isoformat()} ({len(entries)}):" if entries else f"Fleet journal since {since.isoformat()}: nothing.")
    return out + entries


def main() -> None:
    day_n = (today - SHADOW_FIRST).days + 1
    print(f"# Facts for the brief — {now:%A %d %B %Y, %H:%M} Casablanca")
    print(f"SHADOW: day {day_n} of {SHADOW_DAYS}" if 1 <= day_n <= SHADOW_DAYS else "SHADOW: off")
    print()

    print("## Sentinel (servers, sites, backups, domains)")
    code, out = run(["python3", "/usr/local/lib/sentinel/sentinel-check", "--digest", "--dry-run"], timeout=180)
    body = [l for l in out.splitlines() if l.strip() and not l.startswith("--- would post")]
    print("\n".join(body[:40]) if code == 0 and body else f"Sentinel: UNAVAILABLE (exit {code})")
    print()

    rec = plane("recent", f"--since={since.isoformat()}", "--limit=50")
    changed = rec.get("projects", {}) if rec.get("ok") else {}
    if not rec.get("ok"):
        print(f"Plane recent changes: UNAVAILABLE — {rec.get('error')}\n")

    for key, folder, name in CLIENTS:
        print(f"## Client: {name} (Plane {key})")
        print("\n".join(plane_facts(key, changed.get(key, []))))
        print("\n".join(vault_facts(folder)))
        print()
        time.sleep(2)  # Plane allows 60 requests a minute

    print("## Internal")
    for key, name in INTERNAL:
        print(f"### {name} (Plane {key})")
        print("\n".join(plane_facts(key, changed.get(key, []))))
        print()
        time.sleep(2)


if __name__ == "__main__":
    main()
