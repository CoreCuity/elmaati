---
name: fleet-plane
description: "Where the work stands: read Plane (read-only) for Adolia, Odae, Désirs and CoreCuity's internal boards — open work, what is blocked, what is due, what changed since a date, one work item with its comments."
version: 1.0.0
author: CoreCuity
license: proprietary
platforms: [linux]
metadata:
  hermes:
    tags: [Plane, Work, Status, Fleet]
    related_skills: [fleet-vault, fleet-health, fleet-task]
---

# fleet-plane — where the work stands

Plane is the board the founders and the fleet report into. You read it with one
command, `fleet-plane`. It is **read-only**: you cannot create, edit, move or
comment on anything with it. There is no other way for you to reach Plane.

## What you can see

Six projects, and nothing else:

| Key | Board |
|---|---|
| ADOL | Adolia |
| ODAE | Odae |
| DD | Désirs d'Orient |
| AHQ | Core Agents HQ — the fleet's own work |
| CORE | CoreCuity internal |
| OPS | Agency Ops |

Any other project is refused (exit code 4). That is by design: do not look for
another way in, and do not guess what is on a board you cannot see.

## Commands

```
terminal(command="fleet-plane projects")
terminal(command="fleet-plane issues ADOL")                          # open work, newest change first
terminal(command="fleet-plane issues ADOL --state=Blocked")
terminal(command="fleet-plane issues ODAE --all --updated-since=2026-09-01")
terminal(command="fleet-plane issue ADOL-402 --comments=5")          # one item, its text, last comments
terminal(command="fleet-plane recent --since=2026-10-02")            # everything that changed, all six boards
```

Output is JSON: `ok`, then the data. Each work item carries `key`, `name`,
`state`, `priority`, `assignees`, `labels`, `due`, `updated`.
"Open" means not done and not cancelled; **Blocked counts as open** even on a
board where Plane files it under cancelled.

Exit code 4: your request was refused — fix it once, per `error`.
Exit code 5: Plane did not answer — say so; do not retry in a loop.

## How to use what you read

- Quote the key (`ADOL-402`) with every item you mention, so a founder can open it.
- Give dates: "updated 2 Oct", "due 8 Oct". An item not updated for 14 days or
  more is **stale** — say so.
- Plane holds the state of the work; your vault holds what the client is and
  what the founders decided (`fleet-vault`). When they disagree, say both.
- Something that should be on the board and is not: tell the founders. You
  cannot add it yourself.
- Never paste a whole board into a channel. Summarise: what is blocked and on
  whom, what is due this week, what changed.
