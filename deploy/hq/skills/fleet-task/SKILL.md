---
name: fleet-task
description: "Delegate heavy read-only work (research, analysis, repo or data digging for a client) to a headless CLI run (Claude Code, Codex, Antigravity or OpenCode) via fleet-task, and get a receipt."
version: 1.1.0
author: CoreCuity
license: proprietary
platforms: [linux]
metadata:
  hermes:
    tags: [Delegation, Claude, Codex, Antigravity, OpenCode, Receipts, Fleet]
    related_skills: [hermes-agent]
---

# fleet-task — delegate heavy work to a CLI run

You are the foreman. Heavy work — reading many files, digging through a client's
data, long analysis — goes to a headless CLI run. You hand it a clear task, it
comes back with an answer and a **receipt**. You check the receipt, then report.

## The only way to start a CLI run

```
terminal(command="fleet-task --target=/home/svc-hermes/work/<client> --context-id=<kanban task id> --requested-by=<founder> --consumer=hermes:<your profile> --prompt='<the task>'", timeout=1900)
```

- `<client>` is one of: `adolia`, `odae`, `desirs`, `internal` (CoreCuity's own
  work). Never mix clients in one run.
- Long task text: write it to a file in that client folder and pass
  `--prompt-file=<path>` instead of `--prompt=`.
- Optional: `--quality=high` for hard reasoning (default `std`), `--chain=…` to
  choose who runs it (below). Nothing else is accepted.
- **Never run `claude`, `codex`, `agy` or `opencode` directly.** They are blocked,
  and fleet-task is where the budget, the read-only rule and the receipts live.

## Who runs it (`--chain`)

Leave `--chain` out and the run goes to Claude Code, then Codex if Claude is
capped or logged out. Name a chain only when you have a reason:

| `--chain=` | Runs on | Use it for |
|---|---|---|
| *(none)* | Claude Code, then Codex | the default for everything |
| `codex` | Codex | when Claude is capped and you do not want to wait |
| `antigravity` | Antigravity (Gemini) | very long material, images, video |
| `opencode` | OpenCode, free models | a second opinion on CoreCuity's own material |

A chain can list several, tried in order: `--chain=antigravity,claude`. No spaces.

- **Antigravity answers from the files and the web only.** In a read-only run it
  cannot call a connected tool or run a command; a task that needs one comes
  back failed with `read-only run stopped: agy blocked …`. Send that task to the
  default chain instead.
- **OpenCode's free models are the weakest of the four** and are run by outside
  providers. Check their answer against the files before you repeat it, and keep
  client material off them unless a founder said otherwise for that task.

## What a run can and cannot do

- **Read only.** It can read files, search, and fetch the web. It cannot edit files,
  run write commands, or change anything. That is enforced by the CLI, not by
  asking nicely.
- Code, config, storefront and server changes are **not** delegated in fleet v1.
  Write a task pack for the founders (the ticket, the context, the acceptance
  check) and put it on the board.
- One run at a time, at most 20 per hour. If busy, fleet-task waits up to 15 min.

## The receipt (stdout, JSON) — read it every time

| Field | Use |
|---|---|
| `ok`, `exit_code` | Did it work (see exit codes below) |
| `output` | The answer. Check it against the task before you trust it. |
| `call_id` | **Put this on the kanban task** as the proof of work (design rule 4). |
| `provider`, `model`, `attempts` | Which CLI answered; earlier attempts show fallbacks. Say which one when you report. |
| `duration_ms`, `usage` | Cost/time, for the daily summary |

Exit codes and what to do:

| Code | Meaning | Do |
|---|---|---|
| 0 | done | verify `output`, attach `call_id`, report |
| 1 | every provider failed | read `attempts[].error`. "login" / "auth" → tell the founders in #alerts: *fleet CLI login expired, run the login steps in core/ai-router/docs/HQ-DEPLOY.md*. "limit" → wait until the reset time shown, retry once |
| 2, 3 | refused / too long | split or rephrase the task once; then escalate |
| 4 | fleet-task refused the request | fix the call per the error; do not look for a way around it |
| 6 | 20 runs this hour already | park the task, retry after the time in `error` |
| 7 | another run held the slot 15 min | retry once later |

Never retry in a loop. Two failures on the same task → mark it `blocked` on the
board with the receipt's error and tell the founders.

## Good delegation

- One question per run, with the expected shape of the answer ("reply with a
  table of …", "list the 5 …").
- Say where to look ("the files in this folder", "the Meta account for Adolia").
- The run knows nothing about the conversation — put all the context it needs in
  the task text.
