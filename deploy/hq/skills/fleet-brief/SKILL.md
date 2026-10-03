---
name: fleet-brief
description: "Write the founders' 08:00 daily brief for #briefing from the facts block the brief job hands you: in plain words, what needs a founder today and how each client is doing. Used by the scheduled brief job; also when a founder asks for 'the brief' now."
version: 2.0.0
author: CoreCuity
license: proprietary
platforms: [linux]
metadata:
  hermes:
    tags: [Brief, Status, Fleet]
    related_skills: [fleet-plane, fleet-vault, fleet-health]
---

# fleet-brief — the 08:00 brief

**The goal:** a founder reads it in **one minute**, on a phone, half awake, and
knows what to do today. If they have to decode a word, the brief failed.

## Material

The scheduled job runs a facts script first; its output (starting
`# Facts for the brief`) is in your prompt. **Write only from that block.**
Do not call tools, do not add what you remember, do not guess. If a source
says UNAVAILABLE, say so plainly in the first line ("I could not read Plane
this morning").

When a founder asks for the brief outside the job, get the same facts with
`terminal(command="python3 ~/.hermes/scripts/fleet-brief-facts.py", timeout=300)`.

## The facts are raw; you translate them

The facts block is written for you, not for the founders. It is full of
ticket codes, board states and system words. **None of that goes into the
brief as is.** Turn each item into what a person would say out loud.

| Facts say | Brief says |
|---|---|
| `ODAE-71 … (In Progress; due 2026-09-24) OVERDUE` | "The Odae clearance campaign is still marked as running; it ended around 24 Sep. Close it or say what's left." |
| `ADOL-399 Meta for WooCommerce connect blocked — partner access insufficient` | "Connecting Adolia's shop to Meta is stuck on access rights — Massine's (since 8 Jul)." |
| `waiting · On Houda: the real delivery cost per order` | "Still waiting on Houda for Odae's delivery cost (asked 14 Sep)." |
| Sentinel "All clear — 42 targets watched" | "Servers and sites: all fine." |

## Shape (≤ 1,200 characters)

```
**Good morning — Sat 3 Oct**

**Needs you today**
1. <who> — <one plain action, one line>
2. …
3. …

**Adolia** — <one or two plain sentences: how it's going, what we're waiting on>
**Odae** — …
**Désirs d'Orient** — …

**Servers and sites** — <"all fine" or the problem in plain words>
**Our own work** — <one sentence, only if something moved or is stuck>

_Trial day N of 5 — reply with anything unclear or wrong._
```

## Rules

1. **Plain words only.** Write it the way you'd say it to a friend on the
   phone. No ticket codes in sentences, no board words ("backlog", "in
   review", "stale", "board", "overdue items"), no tool or system names
   (Plane, Sentinel, CTWA, MCP, POS, Odoo module names), no abbreviations
   (MAD, SOW, LP, DNS) — say "dirhams", "the quote", "the landing page",
   "the domain". People by first name.
2. **"Needs you today": at most 3**, most important first, each one line,
   starting with the founder's first name (Najlaa / Massine / both). An item
   belongs here only if a founder can act on it today. If nothing does, write
   "Nothing needs you this morning." and skip the list.
3. **One or two sentences per client.** How it's going, then what we're
   waiting on and from whom, with the date we asked. Nothing changed and
   nothing waiting → "Quiet."
4. **Leave out old clutter.** Anything not touched in over a month that
   nobody is waiting on is not news — leave it out. If a client's to-do list
   is badly out of date, say it once at the end: "Tidy-up: Odae's to-do list
   still shows finished work as open."
5. **Dates as people say them:** "since 24 Sep", "by Monday". No ISO dates.
6. **Servers and sites:** one short line. Pending updates and reboots are not
   news.
7. **Never invent.** Not progress, not impact, not reasons. If the facts only
   say it's overdue, write that it's "still marked open", not that it
   "blocks" anything.
8. No money, no customer data, no secrets, no server names or paths.
9. **Ticket codes:** only in "Needs you today", only in brackets at the very
   end of the line, so a founder can find it: `… (ODAE-71)`.
10. **A paused client** (the facts say PAUSED) gets one line: "Odae — paused
    since 3 Oct." Never in "Needs you today", unless its site is down.
11. Under 1,200 characters. Shorter is better.

## Trial footer

While the facts block says `SHADOW: day N of 5`, end with
`_Trial day N of 5 — reply with anything unclear or wrong._`
With `SHADOW: off`, no footer.
