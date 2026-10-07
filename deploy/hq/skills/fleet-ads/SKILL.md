---
name: fleet-ads
description: "Write the daily Adolia ads check for #adolia from the facts block the ads job hands you: what the ads cost yesterday and this week, per audience, what tripped, who changed what, and at most one proposal for a founder. Also when a founder asks 'how are Adolia's ads doing?'."
version: 1.0.0
author: CoreCuity
license: proprietary
platforms: [linux]
metadata:
  hermes:
    tags: [Ads, Meta, Adolia, Fleet]
    related_skills: [fleet-brief, fleet-vault]
---

# fleet-ads — the daily Adolia ads check

**The goal:** a founder knows in under a minute whether Adolia's ads are fine,
and gets the same answer they would have reached checking Ads Manager
themselves.

## Material

The scheduled job runs a facts script first; its output (starting
`# Facts for the Adolia ads check`) is in your prompt. **Write only from that
block.** The script did the arithmetic: copy its numbers, never recompute or
round differently. Do not call tools. If it says UNAVAILABLE, say so in the
first line and stop.

When a founder asks outside the job, get the same facts with
`terminal(command="python3 ~/.hermes/scripts/fleet-ads-facts.py", timeout=300)`.
For a narrower question, `fleet-meta` answers directly (read-only, Adolia only):
`fleet-meta live adolia`, `fleet-meta results adolia --level=adset --since=… --until=…`,
`fleet-meta changes adolia --since=…`.

## Shape (plain words, ≤ 1,500 characters)

```
**Adolia ads — Fri 2 Oct**
<one line verdict: "All normal." or the one thing to look at>

**Yesterday:** €20 → 19 WhatsApp conversations (€1.05 each).
**This week, per audience:** Casa-Rabat €0.58 · Engagés IG €0.86 · Autres villes €0.96 · Tanger €1.63 per conversation.
**Watch:** <only tripped checks and ad problems, in plain words — omit the line if none>
**Changes in the account:** <who changed what, plain words — "none">
**Proposal:** <at most one, see rules — omit the line if none>

_Shadow day N of 10 — compare with your own check and reply with anything different._
```

## Rules

1. **Plain words.** "Audience" not "ad set", "WhatsApp conversations" not
   CTWA/messaging events, "cost per conversation" not CPL/CPA. No IDs. Euros
   with two decimals as the facts give them.
2. **The founders' standing instructions in the facts are binding.** Read them
   before writing anything that sounds like advice. In particular: while those
   instructions say an audience test is running until a date, you may say
   which audience is cheapest so far, but **never propose moving budget
   between audiences before that date**. The date lives in the instructions,
   not here; once it has passed and the instructions have not changed, say
   once that the test's read is due and a founder has not recorded it yet.
   Never propose turning Advantage+ on, reactivating an old campaign, or
   archiving anything.
3. **One day is noise.** A single day with 2 conversations proves nothing.
   Judge on the week and on "since the campaign started"; mention yesterday only
   as the headline total.
4. **Proposals: at most one**, only when a tripped check or an ad problem calls
   for it, written as "Proposal for Najlaa/Massine: …, because …". You never
   change anything yourself: spend, budgets, pausing and activating are a
   founder's decision in #approvals.
5. **Changes:** say who did it and what, in words ("Meta charged the card
   €260.75"; "Najlaa paused the Tanger audience"). Meta's own automatic
   housekeeping is not news.
6. **Never invent** a reason, a trend or a result the facts do not show.
7. No customer names or messages, no phone numbers, no IDs.

## Shadow footer

While the facts say `SHADOW: day N of 10`, end with
`_Shadow day N of 10 — compare with your own check and reply with anything different._`
With `SHADOW: off`, no footer.
