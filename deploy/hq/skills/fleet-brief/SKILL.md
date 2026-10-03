---
name: fleet-brief
description: "Write the founders' 08:00 daily brief for #briefing from the facts block the brief job hands you: per client what stands, what is blocked and on whom, what is due, what changed, plus Sentinel alerts. Used by the scheduled brief job; also when a founder asks for 'the brief' now."
version: 1.0.0
author: CoreCuity
license: proprietary
platforms: [linux]
metadata:
  hermes:
    tags: [Brief, Status, Fleet]
    related_skills: [fleet-plane, fleet-vault, fleet-health]
---

# fleet-brief — the 08:00 brief

**The goal:** a founder reads it in under two minutes and does not need to
ask "where do we stand with X?" today.

## Material

The scheduled job runs a facts script first; its output (starting
`# Facts for the brief`) is in your prompt. **Write only from that block.**
Do not call tools, do not add what you remember, do not guess. If a source
says UNAVAILABLE, the brief says so in its first line.

When a founder asks for the brief outside the job, get the same facts with
`terminal(command="python3 ~/.hermes/scripts/fleet-brief-facts.py", timeout=300)`.

## Shape (Discord markdown, ≤ 2,500 characters)

```
## 🌅 Brief · Sat 3 Oct
<one line: the single thing that most needs a founder today — or "Nothing needs you this morning.">

**🛰️ Systems** — <"all clear, 42 watched" or each open problem in a few words>

**Adolia** — <one line: where it stands>
• Blocked: <KEY what — on whom, since when>
• Due: <KEY what — date>
• Waiting on client: <what — since when>
• Changed: <KEY what moved>

**Odae** — …
**Désirs d'Orient** — …

**Internal** — <only what is blocked, due this week, or changed; one line each>

<shadow footer, see below>
```

## Rules

1. **Lead with what needs a founder.** The first line after the title is the
   one action that matters most today. Never a greeting.
2. **Every item carries its key and a date** — `ADOL-399 (since 8 Jul)`,
   `ODAE-71 (due 24 Sep, overdue)`. A founder must be able to open it.
3. **Say on whom.** Blocked and waiting items name who must act: a founder by
   first name, the client contact by role and first name, or "CoreCuity".
4. **Omit empty lines.** No "Blocked: none". A client with nothing blocked,
   due or changed gets one line: "<Client> — quiet; nothing due."
5. **Old noise is one line, not a list.** "Long overdue" items and "untouched
   14+ days" items are summarised: "CORE: 10 items overdue since May — board
   needs a cleanup". Name a stale item only if it is client-facing work.
6. **Systems:** if Sentinel is all clear, one line. Pending updates and
   reboots are not problems — do not list them.
7. **Vault waiting items are dated history.** Mention one only if nothing in
   Plane covers it, and give its date: "(noted 24 Sep)".
8. **No money, no customer data, no secrets, no server paths.** Client
   contacts by role and first name only.
9. **Never invent progress or impact.** If the facts do not show it, it did
   not happen. Do not say an item "blocks" or "delays" something unless the
   facts say so; an overdue item may simply not have been closed — write
   "overdue, still open on the board".
10. **Internal is three bullets at most**, one per board, blocked and due
    first. Changes are a count ("CORE: 8 items moved since 2 Oct"), never a
    list of keys.
11. Under 2,500 characters. Cut detail before cutting a client.

## Shadow footer

While the facts block says `SHADOW: day N of 5`, end with:

```
_Shadow day N/5 — reply here with anything wrong or missing. A founder judges each brief: "enough to not ask" or not._
```

With `SHADOW: off`, no footer.
