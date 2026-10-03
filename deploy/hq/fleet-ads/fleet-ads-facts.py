#!/usr/bin/env python3
"""fleet-ads-facts — the numbers behind the fleet's daily Adolia ads check (fleet-v1 §3 Ads, §10 phase 2).

Hermes cron runs this before the agent; its stdout is the only material the check is written from.
The script reads and computes; the model explains. Read-only: fleet-meta (GET only, Adolia only) and the
founder-approved vault card. Installed root-owned by core/elmaati/deploy/hq/fleet-ads/install.sh.
"""
from __future__ import annotations

import datetime as dt
import json
import re
import subprocess
from pathlib import Path
from zoneinfo import ZoneInfo

CLIENT = "adolia"
ACCOUNT_TZ = ZoneInfo("America/Los_Angeles")   # Meta reports Adolia's days in this timezone
CARD = Path("/var/lib/fleet-vault/clients/adolia/card.md")
SHADOW_FIRST, SHADOW_DAYS = dt.date(2026, 10, 3), 10
NOISE = ("asa_auto_custom_audience",)          # audiences Meta creates on its own

today = dt.datetime.now(ACCOUNT_TZ).date()
yday = today - dt.timedelta(days=1)


def meta(*args: str) -> dict:
    p = subprocess.run(["/usr/local/bin/fleet-meta", *args], capture_output=True, text=True, timeout=120)
    try:
        return json.loads(p.stdout)
    except ValueError:
        return {"ok": False, "error": f"no answer (exit {p.returncode})"}


def results(since: dt.date, until: dt.date) -> dict:
    r = meta("results", CLIENT, "--level=adset", f"--since={since}", f"--until={until}")
    return {x["name"]: x for x in r.get("rows", [])} if r.get("ok") else {}


def cpc(x: dict | None) -> str:
    if not x:
        return "no delivery"
    c = x.get("conversations_started", 0)
    return f"€{x['spend']:.2f} → {c} conversations" + (f" (€{x['spend'] / c:.2f} each)" if c else " (none)")


def pct(new: float | None, old: float | None) -> str:
    if not new or not old:
        return ""
    return f" ({(new - old) / old * 100:+.0f}% vs the 7 days before)"


def main() -> None:
    day_n = (dt.date.today() - SHADOW_FIRST).days + 1
    print(f"# Facts for the Adolia ads check — {dt.date.today():%A %d %B %Y}")
    print(f"Ad account days are Los Angeles days: 'yesterday' = {yday:%A %d %B}.")
    print(f"SHADOW: day {day_n} of {SHADOW_DAYS}" if 1 <= day_n <= SHADOW_DAYS else "SHADOW: off")
    print()

    acc = meta("account", CLIENT)
    if not acc.get("ok"):
        print(f"META: UNAVAILABLE — {acc.get('error')}")
        return
    print(f"## Account\nStatus: {acc['status']}" + (f" — reason {acc['disable_reason']}" if acc.get("disable_reason") else "")
          + f". Currency {acc['currency']}.\n")

    m = re.search(r"## Standing instructions from the founders\n(.+?)\n## ", CARD.read_text(), re.S) if CARD.exists() else None
    print("## Founders' standing instructions (founder-approved card — binding)")
    print(m.group(1).strip() if m else "UNAVAILABLE: card not readable")
    print()

    live = meta("live", CLIENT)
    if live.get("ok"):
        camps = {c["id"]: c for c in live["campaigns"]}
        on = [s for s in live["ad_sets"] if s["status"] == "ACTIVE"]
        print("## Delivering now")
        for c in (c for c in live["campaigns"] if c["status"] == "ACTIVE"):
            print(f"Campaign: {c['name']} (started {c['start']})")
        for s in on:
            print(f"- audience {s['name']}: €{s['daily_budget']}/day" if s.get("daily_budget") else f"- audience {s['name']}")
        bad = [a for a in live["ads"] if a["status"] in ("DISAPPROVED", "WITH_ISSUES") or a["issues"]]
        print(f"Ads with a problem ({len(bad)}):" if bad else "Ads with a problem: none.")
        for a in bad:
            print(f"- {a['name']}: {a['status']} {'; '.join(a['issues'])}")
        print(f"Not delivering (paused, kept as instructed): {len(live['ad_sets']) - len(on)} audiences.\n")
        start = min((c["start"] for c in live["campaigns"] if c["status"] == "ACTIVE" and c["start"]), default=None)
    else:
        print(f"## Delivering now: UNAVAILABLE — {live.get('error')}\n")
        on, start = [], None

    y = results(yday, yday)
    w = results(yday - dt.timedelta(days=6), yday)
    w0 = results(yday - dt.timedelta(days=13), yday - dt.timedelta(days=7))
    names = [s["name"] for s in on] or sorted(set(y) | set(w))

    tot = lambda d: (sum(x["spend"] for x in d.values()), sum(x.get("conversations_started", 0) for x in d.values()))
    ys, yc = tot({k: v for k, v in y.items() if k in names})
    print(f"## Yesterday ({yday:%a %d %b}), delivering audiences")
    print(f"Total: €{ys:.2f} → {yc} WhatsApp conversations started" + (f" (€{ys / yc:.2f} each)" if yc else ""))
    for n in names:
        x = y.get(n)
        extra = f"; frequency {x['frequency']}; {x.get('blocked_us', 0)} blocked the business" if x and x.get("blocked_us") else ""
        print(f"- {n}: {cpc(x)}{extra}")
    print()

    # Compare with the 7 days before only when both weeks fall inside the current campaign.
    comparable = bool(start) and dt.date.fromisoformat(start) <= yday - dt.timedelta(days=13)
    print(f"## Last 7 days ({yday - dt.timedelta(days=6):%d %b}–{yday:%d %b})"
          + (" vs the 7 before" if comparable else " — no comparison: the campaign is younger than two weeks"))
    for n in names:
        a, b = w.get(n), w0.get(n)
        ca = a["spend"] / a["conversations_started"] if a and a.get("conversations_started") else None
        cb = b["spend"] / b["conversations_started"] if b and b.get("conversations_started") else None
        print(f"- {n}: {cpc(a)}{pct(ca, cb) if comparable else ''}" + (f"; frequency {a['frequency']}" if a else ""))
    print()

    if start:
        s = results(dt.date.fromisoformat(start), yday)
        print(f"## Since the current campaign started ({start})")
        for n in sorted(names, key=lambda n: (s.get(n) or {}).get("cost_per_conversation") or 99):
            print(f"- {n}: {cpc(s.get(n))}")
        print()

    flags = []
    for n in names:
        a, x = w.get(n), y.get(n)
        if not x or x["spend"] == 0:
            flags.append(f"{n}: spent nothing yesterday although switched on")
        elif x["spend"] >= 3 and not x.get("conversations_started"):
            flags.append(f"{n}: spent €{x['spend']:.2f} yesterday with no conversation")
        if a and a["frequency"] > 3:
            flags.append(f"{n}: the same people see it often (frequency {a['frequency']} in 7 days)")
    print("## Checks that tripped (computed, not judged)")
    print("\n".join(f"- {f}" for f in flags) if flags else "None.")
    print()

    ch = meta("changes", CLIENT, f"--since={yday - dt.timedelta(days=1)}")
    rows = [c for c in ch.get("changes", []) if not any(n in (c.get("object") or "") for n in NOISE)] if ch.get("ok") else None
    print(f"## Changes in the ad account since {yday - dt.timedelta(days=1):%d %b} (who changed what)")
    if rows is None:
        print(f"UNAVAILABLE — {ch.get('error')}")
    elif not rows:
        print("None.")
    for c in (rows or [])[:20]:
        if c["what"] == "ad_account_billing_charge" and str(c.get("to") or "").isdigit():
            fr = f": Meta charged the card €{int(c['to']) / 100:.2f}"   # Meta gives cents
        else:
            fr = f" from {c['from']} to {c['to']}" if c.get("from") is not None or c.get("to") is not None else ""
        print(f"- {c['when']} UTC · {c['who']} · {c['what']} · {c['object']}{fr}")


if __name__ == "__main__":
    main()
