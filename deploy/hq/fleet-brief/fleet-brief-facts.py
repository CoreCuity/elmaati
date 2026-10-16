#!/usr/bin/env python3
"""fleet-brief-facts — the facts behind Elmaati's 08:00 brief (fleet-v1 §3, §10 phase 1).

Hermes cron runs this before the agent (`hermes cron create --script`); its stdout is the
only material the brief is written from. Deterministic: the model phrases, it does not fetch.

Sources, all read-only and all already the fleet's:
  Sentinel  /usr/bin/python3 /usr/local/lib/sentinel/sentinel-check --digest --dry-run
  Plane     /usr/local/bin/fleet-plane (6 projects, GET only)
  Vault     /var/lib/fleet-vault (founder-approved cards/timelines + the fleet's journal)
  Meta      /usr/local/bin/fleet-meta (Adolia only, GET only) — counts, never money

Every fact carries its age. A board entry nobody has touched for OLD_DAYS is not news: it is
counted under "old board entries" and never listed as blocked, late or in progress. An edit to
a board entry is labelled as an edit — it says nothing about the real system. (2026-10-07: the
brief had been leading with a July entry for five days and reporting ticket edits as campaign
changes.)

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
INTERNAL = [("AHQ", "Core Agents HQ (the 3D office, not the fleet)"), ("CORE", "CoreCuity (the fleet's own rollout is CORE-22)"), ("OPS", "Agency Ops")]
VAULT = Path("/var/lib/fleet-vault")
SHADOW_FIRST, SHADOW_DAYS = dt.date(2026, 10, 3), 5
STALE_DAYS = 14
LONG_OVERDUE_DAYS = 30
OLD_DAYS = 45            # untouched this long = not news
AGENT_ACCOUNT = "CoreCuity Fleet"   # Plane member the CLI sessions on the founders' Mac also write as
META_CLIENTS = {"adolia"}
BRIEFS = Path("/home/svc-hermes/.hermes/cron/output/376695eabdc0")   # what the fleet-brief job posted

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
    r: dict = {}
    for attempt in range(3):
        code, out = run(["/usr/local/bin/fleet-plane", *args])
        try:
            r = json.loads(out)
        except ValueError:
            r = {"ok": False, "error": f"no answer (exit {code})"}
        if r.get("ok") or "429" not in str(r.get("error")):
            break
        time.sleep(30)  # Plane allows 60 requests a minute; wait the window out
    return r


def asked_before() -> dict[str, list[dt.date]]:
    """Board keys the brief already put under 'Needs you today', newest brief first.
    (2026-10-14: the same decision led the brief seven days running.)"""
    seen: dict[str, list[dt.date]] = {}
    for f in sorted(BRIEFS.glob("*.md"), reverse=True)[:10]:
        try:
            day = dt.date.fromisoformat(f.name[:10])
            text = f.read_text().split("## Response", 1)[1]
        except (ValueError, IndexError, OSError):
            continue
        if day >= today:
            continue
        m = re.search(r"Needs you today\**\s*\n(.*?)(?:\n\s*\n|\Z)", text, re.S)
        keys = set()
        for proj, first, more in re.findall(r"\b([A-Z]{2,5})-(\d+)((?:\s*[/,]\s*(?:[A-Z]{2,5}-)?\d+)*)", m.group(1) if m else ""):
            keys.add(f"{proj}-{first}")   # "(DD-16/DD-14/DD-13)" and "(CORE-32/30/28)" both name three entries
            keys.update(f"{p or proj}-{n}" for p, n in re.findall(r"(?:([A-Z]{2,5})-)?(\d+)", more))
        for key in keys:
            seen.setdefault(key, []).append(day)
    return seen


ASKED = asked_before()


def repeat(i: dict) -> str:
    """' ALREADY ASKED …' when a brief of the last week asked about this entry and nobody touched it since."""
    days = [d for d in ASKED.get(i["key"], []) if (today - d).days <= 7]
    if not days or i["updated"][:10] >= days[0].isoformat():
        return ""
    return f" ALREADY ASKED in 'Needs you' on {len(days)} brief(s) since {days[-1]:%d %b}, untouched since"


def line(i: dict) -> str:
    bits = [i["state"]]
    if i.get("assignees"):
        bits.append("→ " + ", ".join("an agent session (no person assigned)" if a == AGENT_ACCOUNT else a
                                      for a in i["assignees"]))
    if i.get("due"):
        bits.append(f"due {i['due']}")
    bits.append(f"updated {i['updated'][:10]}")
    return f"- {i['key']} {i['name']} ({'; '.join(bits)})" + repeat(i)


def plane_facts(key: str, changed: list[dict]) -> list[str]:
    r = plane("issues", key, "--limit=150")
    if not r.get("ok"):
        return [f"Plane {key}: UNAVAILABLE — {r.get('error')}"]
    every = r["issues"]
    old_cut = (today - dt.timedelta(days=OLD_DAYS)).isoformat()
    old_board = sorted((i for i in every if i["updated"][:10] < old_cut), key=lambda i: i["updated"])
    open_ = [i for i in every if i["updated"][:10] >= old_cut]
    parked = sum(1 for i in open_ if i["state_group"] == "backlog")
    out = [f"Plane {key}: {len(open_) - parked}{'+' if len(every) >= 150 else ''} work items open and touched in the last "
           f"{OLD_DAYS} days" + (f" ({parked} more parked for later — not news)." if parked else ".")]
    blocked = [i for i in open_ if "block" in i["state"].lower()]
    out.append(f"Blocked ({len(blocked)}) — the note under each says on whom and since when:" if blocked else "Blocked: none.")
    for i in blocked[:6]:
        out.append(line(i))
        d = plane("issue", i["key"], "--comments=0")
        why = (d.get("issue") or d).get("description") if d.get("ok") else None
        if why:
            out.append(f"    note: {' '.join(str(why).split())[:320]}")
    week = (today + dt.timedelta(days=7)).isoformat()
    month_ago = (today - dt.timedelta(days=LONG_OVERDUE_DAYS)).isoformat()
    due = sorted((i for i in open_ if i.get("due") and month_ago <= i["due"] <= week), key=lambda i: i["due"])
    out.append(f"Overdue (last {LONG_OVERDUE_DAYS} days) or due within 7 days ({len(due)}):" if due
               else f"Overdue (last {LONG_OVERDUE_DAYS} days) or due within 7 days: none.")
    out += [line(i) + (" OVERDUE" if i["due"] < today.isoformat() else "") for i in due]
    old = sorted((i for i in open_ if i.get("due") and i["due"] < month_ago), key=lambda i: i["due"])
    if old:
        out.append(f"Due date passed more than {LONG_OVERDUE_DAYS} days ago but still being worked ({len(old)}): "
                   + ", ".join(i["key"] for i in old[:12]) + (" …" if len(old) > 12 else ""))
    cut = (today - dt.timedelta(days=STALE_DAYS)).isoformat()
    stale = sorted((i for i in open_ if i["updated"][:10] < cut and i["state_group"] == "started"),
                   key=lambda i: i["updated"])
    out.append(f"In progress but untouched for {STALE_DAYS}+ days ({len(stale)}), oldest first:" if stale
               else f"In progress but untouched for {STALE_DAYS}+ days: none.")
    out += [line(i) for i in stale[:5]]
    out.append(f"Board entries edited since {since.isoformat()} ({len(changed)}) — an edit to the entry, "
               f"NOT a change to the client's systems, ads or site:" if changed
               else f"Board entries edited since {since.isoformat()}: none.")
    if len(changed) > 12:
        out[-1] = (f"Board entries edited since {since.isoformat()}: {len(changed)} — a bulk tidy-up of the list, "
                   f"not {len(changed)} pieces of news. Do not list them.")
    else:
        out += [line(i) for i in changed]
    if old_board:
        out.append(f"Old board entries (open, untouched for {OLD_DAYS}+ days — NOT news, never in 'Needs you'): "
                   f"{len(old_board)}, oldest last touched {old_board[0]['updated'][:10]}.")
    return out


def ads_facts(folder: str) -> list[str]:
    """What the ads did yesterday, in counts. Money stays in the 09:00 ads check."""
    def meta(*args: str) -> dict:
        code, out = run(["/usr/local/bin/fleet-meta", *args])
        try:
            return json.loads(out)
        except ValueError:
            return {"ok": False, "error": f"no answer (exit {code})"}

    live = meta("live", folder)
    if not live.get("ok"):
        return [f"Ads (Meta): UNAVAILABLE — {live.get('error')}"]
    back = [f"Ads (Meta) RECOVERED: {live['recovered']}"] if live.get("recovered") else []
    on = [s["name"] for s in live["ad_sets"] if s["status"] == "ACTIVE"]
    if not on:
        return back + ["Ads (Meta, read this morning): nothing is delivering."]
    bad = [a for a in live["ads"] if a["status"] in ("DISAPPROVED", "WITH_ISSUES") or a["issues"]]
    yday = dt.datetime.now(ZoneInfo("America/Los_Angeles")).date() - dt.timedelta(days=1)  # the account's day

    def convs(a: dt.date, b: dt.date) -> int | None:
        r = meta("results", folder, "--level=adset", f"--since={a}", f"--until={b}")
        return sum(x.get("conversations_started", 0) for x in r["rows"] if x["name"] in on) if r.get("ok") else None

    y, w = convs(yday, yday), convs(yday - dt.timedelta(days=6), yday)
    out = back + [f"Ads (Meta, read this morning): {len(on)} audiences delivering; "
           + (f"{len(bad)} ads with a problem." if bad else "no ad has a problem.")]
    if y is not None and w is not None:
        out.append(f"WhatsApp conversations started: {y} yesterday ({yday:%a %d %b}), {w} over the last 7 days. "
                   f"One day is noise; the 09:00 ads check has the detail.")
    ch = meta("changes", folder, f"--since={yday}")
    if ch.get("ok"):
        # Meta's own automatic audiences and its card charges are housekeeping, not somebody's change.
        rows = [c for c in ch.get("changes", []) if "asa_auto_custom_audience" not in (c.get("object") or "")
                and c.get("what") != "ad_account_billing_charge"]
        out.append(f"Changes made in the ad account since {yday:%d %b} ({len(rows)}): "
                   + "; ".join(f"{c['who']} · {c['what']} · {c['object']}" for c in rows[:4]) if rows
                   else f"Changes made in the ad account since {yday:%d %b}: none.")
    return out


def engagement(folder: str) -> str:
    card = VAULT / "clients" / folder / "card.md"
    m = re.search(r"^engagement:\s*(.+)$", card.read_text(), re.M) if card.exists() else None
    return m.group(1).strip() if m else "active"


def vault_facts(folder: str) -> list[str]:
    out = []
    tl = VAULT / "clients" / folder / "timeline.md"
    if tl.exists():
        text = tl.read_text()
        m = re.search(r"^approved:.*?(\d{4}-\d{2}-\d{2})", text, re.M)
        checked = dt.date.fromisoformat(m.group(1)) if m else None
        waiting = [l.strip() for l in text.splitlines() if "· waiting ·" in l]
        if waiting:
            age = f"last checked by a founder {(today - checked).days} days ago, on {checked}" if checked else "date of last check unknown"
            out.append(f"Waiting items on the founder-approved timeline ({age}; nobody has confirmed since "
                       f"whether they are still open — say 'as of' that date, do not present them as today's state):")
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
    # The system Python, not whatever python3 comes first on PATH: since the 2026-10-15 Hermes update, cron
    # scripts run with Hermes's private Python 3.14 first, which has no PyYAML (brief of 2026-10-16: exit 1).
    try:
        p = subprocess.run(["/usr/bin/python3", "/usr/local/lib/sentinel/sentinel-check", "--digest", "--dry-run"],
                           capture_output=True, text=True, timeout=180)
        code, out, err = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        code, out, err = 124, "", "timed out after 180 s"
    body = [l for l in out.splitlines() if l.strip() and not l.startswith("--- would post")]
    print("\n".join(body[:40]) if code == 0 and body else
          f"Sentinel: UNAVAILABLE (exit {code}: {' '.join(err.split())[-200:] or 'no error text'})")
    print()

    rec = plane("recent", f"--since={since.isoformat()}", "--limit=50")
    changed = rec.get("projects", {}) if rec.get("ok") else {}
    if not rec.get("ok"):
        print(f"Plane recent changes: UNAVAILABLE — {rec.get('error')}\n")

    for key, folder, name in CLIENTS:
        paused = engagement(folder)
        if paused.startswith("paused"):
            # The founder-approved card is the switch: a paused client gets one line, no board read.
            print(f"## Client: {name} — {paused.upper()} (founder decision on the card). No active work; "
                  f"mention it only if Sentinel above shows a problem with its site.\n")
            continue
        print(f"## Client: {name} (Plane {key})")
        if paused != "active":
            print(f"Status on the founder-approved card: {paused}.")
        if folder in META_CLIENTS:
            print("\n".join(ads_facts(folder)))
        print("\n".join(plane_facts(key, changed.get(key, []))))
        print("\n".join(vault_facts(folder)))
        print()
        time.sleep(5)  # Plane allows 60 requests a minute

    print("## Internal")
    for key, name in INTERNAL:
        print(f"### {name} (Plane {key})")
        print("\n".join(plane_facts(key, changed.get(key, []))))
        print()
        time.sleep(2)


if __name__ == "__main__":
    main()
