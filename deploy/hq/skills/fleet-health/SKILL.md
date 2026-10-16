---
name: fleet-health
description: "Answer 'is X up / watched / backed up / expiring' and 'how are the servers' from Sentinel's state — read-only. Use for any status or health question about CoreCuity's servers, sites, shops, backups, domains or credentials."
version: 1.0.0
author: CoreCuity
license: proprietary
platforms: [linux]
metadata:
  hermes:
    tags: [Health, Status, Sentinel, Fleet, Read-only]
    related_skills: [fleet-task]
---

# fleet-health — answer status questions from Sentinel

Sentinel is the fleet's watch. It runs every 15 minutes with no model, checks
every target against a fixed threshold, and posts in #infra-alerts under your
name. You do not run your own probes for things Sentinel already checks: you
read what it found and report it.

## The three reads

**1. What is wrong right now**

```
terminal(command="cat ~/.local/state/sentinel/state.json")
```

`{}` means nothing is open. Otherwise each entry has `sev` (🔴 critical,
🟠 warning), `group`, `subject` and `detail`. The file is rewritten at every run.

**2. A fresh full picture** (takes about 10 seconds, posts nothing)

```
terminal(command="/usr/bin/python3 /usr/local/lib/sentinel/sentinel-check --digest --dry-run", timeout=120)
```

This prints the daily digest as it would be posted now: open problems, the
number of targets watched, and one line per server (pending reboots, updates
waiting, the tool-call log). Always pass `--dry-run`. Without it the command
posts to #infra-alerts.

**3. Is X watched at all**

```
terminal(command="cat /usr/local/lib/sentinel/sentinel.yaml")
```

This file is the complete list: hosts, each client's backups, endpoints,
shops, content checks, domains and credential expiries, plus the thresholds.
`local_only_by_plan` and `not_watched` are deliberate gaps decided by a
founder — report them as decisions, not as problems.

## Rules

- **If it is not in `sentinel.yaml`, it is not watched.** Say exactly that.
  Do not imply cover, and do not go looking for a process or a port to stand
  in for a missing check.
- **A check that is listed and absent from `state.json` passed at the last
  run.** Give the time of that run:
  `terminal(command="systemctl --user status sentinel-check.service | head -8")`.
- **Is Sentinel itself running?** Both timers must be active:
  `terminal(command="systemctl --user list-timers 'sentinel-*'")`. The daily
  digest at 08:00 Moroccan time is the proof of life; a day with no digest
  means the watch is down, and that is the first thing you report.
- **Read-only.** You never restart a service, reload a proxy, edit a file or
  change `sentinel.yaml`. A missing check or a wrong threshold is a task pack
  for the founders (the change is made in the fleet repo, then installed).
- **Other servers are read only through Sentinel.** The fleet key returns one
  thing, the `fleet-status` JSON, and Sentinel already reads it.
- **No customer data.** These checks see infrastructure facts only.

## What Sentinel does not cover

Report these as "not watched", never as "fine":

- what happens inside the AI Receptionist (calls, bookings, conversations)
- the WhatsApp bridge and the daybook job, which run on the founder's Mac
- anything about a client that is not in `sentinel.yaml`

## Reporting pattern

```text
<thing>: <state> — <evidence: check, value, time of the run>

Open: <n> (<subjects>)        or        Open: none
Not watched: <what was asked that Sentinel does not cover>
Recommendation: <one next move, or "nothing to do">
```

One message. No logs pasted. If a founder needs the raw output, they ask.
