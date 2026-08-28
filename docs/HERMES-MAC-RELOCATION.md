# Elmaati relocates — Hermes body moves from server-architect to the Mac

**Status:** PLANNED (2026-07-30). Nothing executed yet.
**Supersedes the *host* choice** in [`HERMES-DEPLOY.md`](./HERMES-DEPLOY.md); every **principle** in that document carries over unchanged.
**Decision drawer:** MemPalace `hq-decisions/voice-jarvis` — pending, to be written on execution.

## Operator decision (2026-07-30)

1. **Relocate, don't duplicate.** One Elmaati, one memory, one Telegram bot, one Discord bot. The body moves to this Mac; the server body is **stopped, not wiped** (rollback in one command, for two weeks).
2. **Phase 1 is fully sealed** — Elmaati gets *no* access to `/Users/najlio`, the repo, or `.palace`. Capability is granted later, deliberately, one ACL at a time.
3. **Rationale:** the Mac is the machine that is actually *on* and actually *in front of the operator*, and the long-term goal is to hand it real local tasks. The server body could never do local work.

## What this trades away — accept it consciously

| | server-architect | this Mac |
|---|---|---|
| Uptime | 24/7 VPS | laptop; sleeps on battery, **FileVault means a reboot needs the operator to unlock before anything runs** |
| Isolation | `elmaati` Linux user, no sudo/docker | `elmaati` macOS user, own primary group, no sudo — **equivalent** |
| Hardening | systemd `MemoryMax=1500M`, `ProtectHome`, `NoNewPrivileges` | **no launchd equivalent** — see *Resource guard* below |
| Headroom | 6 vCPU / 12 GB (shared) | M1 / **8 GB, swap already ~8 GB of 9.2 GB used** |
| Local work | impossible | the whole point (phase 2+) |

**Honest read on phase 1:** a sealed Mac Elmaati does exactly what the server Elmaati already does — messaging, n8n API, webhooks, web, his own home. Phase 1 buys **no new capability**; it moves the body and proves the seal. Keep it short (days, not weeks) and treat phase 2 as the real milestone.

## What Elmaati can and cannot do while sealed

**Can:** shell inside `/Users/elmaati`, HTTP/web, call n8n webhooks, read the n8n + dashboard APIs, run its own node/python, receive and send on Telegram + Discord, run its own cron.

**Cannot** (by design, and this is permanent for anything under the operator's home): read or write the repo, read MemPalace, reach `server-architect` (no SSH key), use the operator's Messages / Mail / Calendar / Notes / keychain — that data lives in `/Users/najlio` and in the operator's own TCC grants. A separate macOS user can never inherit them. If "text Elmaati to handle my messages" is ever a goal, it needs a different mechanism (an API/webhook surface), **not** a filesystem grant.

---

## Phase M0 — Provision the sealed user

```bash
cd /Users/najlio/Projects/corecuity/core/elmaati/scripts
sudo bash mac-provision-elmaati.sh provision   # prompts for the new account password
sudo bash mac-provision-elmaati.sh verify      # must print "seal holds"
```

`uid 502`, **own primary group `elmaati` (gid 502) — not `staff`**. This is load-bearing: `/Users/najlio` is `750 group=staff`, so a default-created user would traverse and list the operator's home. `verify` asserts the negative for the repo, `.palace`, `~/.ssh`, `~/.claude`, the keychain and the Messages DB. **Do not proceed to M1 until `verify` is clean.**

Deliberate non-actions: not in `admin` (no sudo) · not added to FileVault (`fdesetup` untouched — cannot unlock the disk) · no SSH key · Remote Login stays off.

Set a long random password from the manager. It is needed exactly once, for M2.

## Phase M1 — Install Hermes as `elmaati`

Log into the `elmaati` account **once via fast user switching** (already enabled). This session is required for two reasons: it is when macOS TCC prompts can be approved, and a launchd *Agent* needs a live session.

In that session's Terminal:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
hermes --version    # expect >= v0.18.2 (the version running on the server)
```

The installer brings its own Python 3.11 (via uv), Node, portable git, ripgrep, ffmpeg into `~/.hermes/`. Optionally install **Hermes Desktop** in this session as the cockpit — it shares the same config, keys, sessions, skills and memory as the CLI, so it is a UI over the same brain, not a second instance.

Disk: ~43 GB free. The install is a couple of GB. Fine, not roomy.

## Phase M2 — Move the identity (order matters)

Everything durable about Elmaati is either in-repo or on the server. Pull it in this order — **the bot cutover must be strictly sequential**, because a Telegram token allows only one polling consumer and a Discord bot token only one gateway session. Two live gateways = 409 conflicts and duplicated replies.

1. **From the operator account**, stage the transfer (the repo is the source of truth for the persona):
   ```bash
   scp architect@84.247.138.95:'~/.hermes/config.*' ~/Projects/corecuity/core/elmaati/tmp-migration/
   # also: .env (OPENROUTER_API_KEY, GOOGLE_API_KEY), atelier profiles, kanban board, skills/, memory/
   ```
   Persona: copy `core/elmaati/agents/elmaati-soul.md` → `/Users/elmaati/.hermes/SOUL.md`. Back up the stock file as `SOUL.md.stock` first, exactly as on the server. **The repo copy stays the source of truth**; `~/.hermes/` is operational scratch only — the same GLOBAL RULE #0 carve-out the server deployment already runs under.
2. **Stop the server body first:**
   ```bash
   ssh architect@84.247.138.95 'systemctl --user stop hermes-serve && systemctl --user disable hermes-serve'
   ```
   Do **not** wipe `~elmaati` on the server. That is the rollback.
3. **Then** start the Mac gateway and re-bind the bots (same Telegram token, same Discord app `Elmaati#1317`), still locked to operator IDs only.
4. **Re-authenticate, do not copy tokens.** Run `hermes auth add openai-codex` fresh on the Mac (device flow). Copied OAuth material is machine-bound and a bad habit. The ToS caveat on subscription OAuth through a third-party daemon is unchanged and operator-accepted.
5. Verify `hermes send` reaches the operator's Telegram DM (the home channel) from the Mac.

Timezone is already `Africa/Casablanca` — nothing to set.

Delete `core/elmaati/tmp-migration/` when done; it holds secrets.

## Phase M3 — Always-on

Two mechanisms; start with the first.

- **LaunchAgent** (`hermes gateway install` registers this): restart-on-crash, starts with the `elmaati` login session. Survives display sleep and switching back to the operator account. Does **not** survive a reboot unless someone logs into `elmaati` again.
- **Promote to LaunchDaemon** after the first stable week: a plist in `/Library/LaunchDaemons/` with `UserName: elmaati` starts at boot with no login needed. With FileVault, that still means *after* the operator unlocks the disk — unavoidable, and correct.

Power: AC already has `sleep 0`, so plugged in it stays up. On battery it sleeps and cron jobs are missed — never rely on the watchdog while unplugged.

### Resource guard (there is no `MemoryMax` on macOS)

8 GB with swap already near-exhausted is the sharpest constraint on this box. In the launchd plist:

```xml
<key>ProcessType</key><string>Background</string>
<key>LowPriorityIO</key><true/>
<key>Nice</key><integer>10</integer>
```

`ProcessType: Background` puts it in the throttled QoS tier so it yields to foreground work. Then add a self-check cron that pages the operator if RSS exceeds ~1.5 GB (matching the server's ceiling) — a soft ceiling, enforced by alert rather than by the kernel. Keep Docker Desktop quit unless needed.

## Phase M4 — Watchtower (Hermes-native, NO n8n)

**CORRECTED 2026-07-30.** An earlier draft of this phase specified an *n8n execution watchdog with its own scoped n8n API key*. That is wrong twice over: [[Elmaati OS blueprint v2]] (2026-07-18) explicitly **dropped the scoped-n8n-API-key project** and retired "n8n workflows own orchestration" in favour of Hermes-native orchestration — and the live data does not justify a watchdog anyway.

**Measured 2026-07-30 (full retained history, 7 days, `hasMore: false`):** 35 executions, **two** workflows, **zero failures**.

| Workflow | id | Cadence | Failures |
|---|---|---|---|
| YouTube Analytics Sync (DB) | `G1eUYZtTVyQ0rYLc` | 4×/day (05,11,17,23 UTC) | 0 |
| AI News Digest | `GAuoKVQq3DnghsFN` | 1×/day (13 UTC) | 0 |

Active but **never fired** in that window: `lim-call-anchor` (`rZToLrFuJnEM02Od`), `YT Channel Intel` (`BuFfey0jehzGB5CV`), `Error Monitor — Auto Diagnose` (`Z6KGfB87L5nktu6O`), `discord-inbound` (`kdQkdnoNyst6mMFi`). The last two are **webhook** workflows — zero executions means nobody called them, not that they are broken. **`lim-call-anchor` is LiveItMaghribi, a paying client: confirm that call flow is genuinely retired before anyone deletes it.**

Both live crons serve SignGazer/content-engine, which is itself on the replacement list. Five cron jobs a day with a perfect success rate does not need a monitor; it needs a successor. Two scheduled HTTP calls port to a Hermes cron + skill directly.

### What the watchtower actually watches

The blueprint's "cheap read-only watchtower over the frozen legacy **while it still serves**" — and what still serves is the **product**, not the pipeline. Plain HTTPS probes, which work perfectly while sealed (no API keys, no filesystem grant, no SSH):

| Surface | Check | Verified 2026-07-30 |
|---|---|---|
| Receptionist voice (`rec.corecuity.com/health`) | HTTP 200 | 200 ✅ **client-facing, highest stakes** |
| Receptionist dashboard (`rcpt-hq.corecuity.com`) | HTTP 200 | 200 ✅ |
| `dashboard.corecuity.com` | HTTP 2xx/3xx | 307 (up, slated for deletion — probe until decommissioned, don't fix) |

1. **Watchtower**, every 15 min — probe the table above, alert on Telegram only on a state *change* (up→down, down→up). No cry-wolf on a single timeout: two consecutive failures before paging.
2. **Morning briefing**, 07:30 Africa/Casablanca — surface states overnight, anything that flapped. **Sealed-phase limitation, stated honestly:** receptionist call counts live in on-box telemetry reachable only via `sudo -u receptionist`, and Elmaati has no SSH key — so call volume is *not* in the phase-1 briefing. It arrives when the receptionist gets a read API, not via a filesystem grant. Maâllem register: economical, decisive.

Casting order unchanged: Cloudflare → NVIDIA → OpenRouter cheap → gpt-5.5 escalation. **Kanban contracts only on protocol-reliable models** — gemini-flash fails the 4/4 completion protocol and stays interactive-analysis-only (finding from the 2026-07-18 smoke test).

Casting order unchanged: Cloudflare → NVIDIA → OpenRouter cheap → gpt-5.5 escalation. **Kanban contracts only on protocol-reliable models** — gemini-flash fails the 4/4 completion protocol and stays interactive-analysis-only (finding from the 2026-07-18 smoke test).

Memory bridge: nightly one-block operational summary into the drop path `tools/daybook/scripts/daily_scribe.py` ingests. **This needs a write grant**, so it waits for phase 2 — until then, have him post the summary to Telegram and paste it in.

## Gates before phase 2

- Seal spot-check still clean (`verify` re-run) — no writes anywhere outside `/Users/elmaati`.
- Watchdog alerts are trustworthy: no cry-wolf, no missed failures **during plugged-in hours**.
- No memory-pressure regression the operator can feel while working.
- Cost stays negligible.

## Phase 2 preview — the first grant (do NOT run yet)

When the gates pass, the smallest useful grant is read-only repo + a write-only workshop:

```bash
# traverse the operator's home without being able to list it
sudo chmod +a "user:elmaati allow search" /Users/najlio /Users/najlio/Projects
# read-only across the repo (code + MemPalace become readable)
sudo chmod -R +a "user:elmaati allow list,search,readattr,readextattr,read" \
  /Users/najlio/Projects/corecuity
# his own bench, the only place he may write
mkdir -p /Users/najlio/Projects/corecuity/atelier/elmaati
sudo chmod -R +a "user:elmaati allow list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,read,write,append,delete" \
  /Users/najlio/Projects/corecuity/atelier/elmaati
```

This keeps every artifact **inside the repo** (GLOBAL RULE #0 satisfied) and gives him a real work surface: research notes, drafts, generated scripts, and patch files the operator reviews and applies. Note that read access to `.palace` makes MemPalace legible to him — decide that explicitly, it is the most sensitive read in the list.

Git push rights and the daybook write are phase 3, and need their own review plus a rule #0 amendment drawer.

## Rollback

```bash
# Mac: stop and unload
sudo launchctl bootout system/org.nousresearch.hermes 2>/dev/null   # or: launchctl unload the agent
# Server: bring the body back (bots re-bind to the server gateway)
ssh architect@84.247.138.95 'systemctl --user enable --now hermes-serve'
# Full teardown of the Mac account
sudo bash core/elmaati/scripts/mac-provision-elmaati.sh remove
```

Blast radius of a failed pilot: `/Users/elmaati` and the bot tokens. Nothing else, by construction.
