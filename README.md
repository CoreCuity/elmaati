# Elmaati — the CoreCuity fleet

Elmaati is CoreCuity's foreman agent: a Hermes daemon (`svc-hermes`) on
corecuity-HQ with three workers — Sentinel, Ads, Clerk. The design is
[`docs/architecture/fleet-v1.md`](../../docs/architecture/fleet-v1.md) in the
HQ repo; the operating blueprint is [`docs/ELMAATI-OS.md`](docs/ELMAATI-OS.md).

This repo is the source of truth for everything installed on the box. Never
edit the installed copies: change here → commit → push → run the installer
named in each file's header.

```text
agents/        SOUL of each profile (installed root-owned: an agent cannot
               rewrite its own instructions)
branding/      avatar
deploy/hq/     everything that runs on corecuity-HQ
  restore-hermes.sh          rebuild the Hermes body from the attic backup
  hermes-fleet-fixes.sh      Phase 0 hygiene (tokens, approvals, nightly restart)
  hermes-nightly-restart.sh  quiet planned restart (upstream #58817)
  fleet-profiles.sh          create sentinel / ads / clerk
  fleet-discord.yaml, discord-permissions.py   Discord HQ layout
  fleet-audit/               tamper-evident tool-call log + fleet-kill switch
  fleet-task, fleet-task-install.sh, skills/fleet-task/
                             the only way the fleet starts a CLI run
                             (read-only, budgeted, receipts via ai-router task)
  fleet-cli-update*.sh       weekly self-checking update of the CLI seats
docs/          blueprint + market research
```

The CLI runs themselves go through [`core/ai-router`](../ai-router)
(`ai-router task`); its HQ runbook is `core/ai-router/docs/HQ-DEPLOY.md`.
