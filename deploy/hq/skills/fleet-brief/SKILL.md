---
name: fleet-brief
description: "Write the founders' 08:00 daily brief for #briefing from the facts block the brief job hands you: in plain words, what needs a founder today and how each client is doing. Used by the scheduled brief job; also when a founder asks for 'the brief' now."
version: 3.1.0
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

**Meta access is CoreCuity's, never a client's.** One CoreCuity token reads
every client's ads. Never write "Adolia's ads access" or "Adolia's token".
If the facts say a founder must issue a new token, say that (first line).
If they say Meta refused the token and it "often clears", write one calm
line: "Meta refused our access this morning; no action yet." Never tell a
founder to renew unless the facts say so. A `RECOVERED` line gets one
sentence: "Meta reads work again since <time>; yesterday's alarm is over."

When a founder asks for the brief outside the job, get the same facts with
`terminal(command="/usr/bin/python3 ~/.hermes/scripts/fleet-brief-facts.py", timeout=300)`.

## The facts are raw; you translate them

The facts block is written for you, not for the founders. It is full of
ticket codes, board states and system words. **None of that goes into the
brief as is.** Turn each item into what a person would say out loud.

| Facts say | Brief says |
|---|---|
| `ODAE-71 … (In Progress; due 2026-09-24) OVERDUE` | "The Odae clearance campaign is still marked as running; it ended around 24 Sep. Close it or say what's left." |
| `Board entries edited since … : ADOL-395 Live campaign … (updated 2026-10-05)` | nothing about the campaign. At most: "the Adolia ads task was updated on the list." |
| `Ads (Meta…): 4 audiences delivering … 4 yesterday, 107 over the last 7 days … Changes: none` | "Ads are running; 107 WhatsApp conversations this week. Nobody changed anything." |
| `Waiting items … last checked by a founder 12 days ago, on 2026-10-03` | "As of 3 Oct we were waiting on Ismail for the video rights — is that still open?" |
| `Old board entries (open, untouched for 45+ days …): 51` | nothing, or once at the end: "Tidy-up: Adolia's list still shows 51 old entries as open." |
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

**Still open** — <items marked ALREADY ASKED, one line, only if any>

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
   **Never repeat yesterday's ask by habit:** an item qualifies only if the
   facts list it as blocked, late or due this week — old board entries and
   dated waiting items never do. A server or site problem that has been open
   for days belongs under "Servers and sites", with how long it has been open
   if the facts say so.
   **An entry marked `ALREADY ASKED` never goes in "Needs you today"** and
   is not repeated in its client's sentences either: the founders saw it
   yesterday and nobody touched it since. Put all of them in ONE line at the
   very end, before the footer: "**Still open** — <short plain names, comma
   separated> (asked since <the earliest date>)." No ticket codes, no reasons,
   no nagging. When a founder edits the entry the mark disappears and it may
   return to the top. If every candidate is marked, write "Nothing new needs
   you this morning." instead of the list.
   **An entry the facts mark `URGENT` always goes first in "Needs you today"**
   (it is never marked ALREADY ASKED), and never in "Still open".
3. **One or two sentences per client.** How it's going, then what we're
   waiting on and from whom, with the date we asked. "How it's going" comes
   from the client's `This week on the board` line when nothing was edited
   since yesterday: say in plain words what was finished and what is being
   worked on this week ("This week: the test copy of the new server was
   checked and fixed; the switch-over is still being prepared."). Write
   "Quiet." only when that week line says nothing was edited or finished.
   **Never write "No new updates"** — say "Quiet since yesterday" and then
   the week.
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
   - **An edited board entry is not an event.** "Board entries edited" means
     somebody changed a line on the to-do list. It never means the campaign,
     the site, the server or the client changed. What the ads did comes only
     from the `Ads (Meta…)` lines; what the servers did only from Sentinel.
   - **A waiting item is as old as its last check.** The facts give that
     date. Say "as of <date>"; never "still waiting" as if you had checked
     this morning. Once the last check is more than 14 days old, do not repeat
     the items: write once, at the end, "Tidy-up: the notes on <client> were
     last checked on <date>."
   - **An entry's "updated" date is when somebody edited the line**, not when
     anybody checked with the client. Never write "last checked <date>" or
     "asked again on <date>" from it; use the date the note itself gives.
   - **"Founder-approved notes: … approved <date>"** is for you, not the
     founders. Mention it only as a tidy-up at the end, and only when it is
     more than 14 days old and the week line shows work: "Tidy-up: the notes
     on <client> were approved on <date>; the work has moved since."
   - **"An agent session" is not a person.** Work assigned to it was created
     from a founder's own working session. Never address it to anyone and
     never call it the fleet's work; do not put it in "Needs you today" unless
     the facts name a person.
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
