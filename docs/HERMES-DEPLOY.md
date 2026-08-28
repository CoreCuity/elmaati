# Elmaati on Hermes — Deployment Plan

> [!IMPORTANT]
> **2026-07-30 — HOST CHANGE PLANNED.** The operator decided to **relocate** the body from server-architect to the Mac (one identity, one memory, one bot pair; server body stopped-not-wiped as rollback), starting fully sealed with no repo access. See [`HERMES-MAC-RELOCATION.md`](./HERMES-MAC-RELOCATION.md). Every *principle* below still holds — only the host changes. This document remains the record of the server deployment.

**Status 2026-07-18:** Phase 1 DONE — user `elmaati` (uid 1001, no sudo/docker), Hermes **v0.18.2** at `~/.local/bin/hermes`. Phase 2 backend DONE — linger enabled, `hermes-serve.service` (user unit, `127.0.0.1:9119` verified, MemoryMax=1500M) active. Persona DONE — Maâllem text-surface SOUL deployed from `core/elmaati/agents/elmaati-soul.md` (source of truth; stock backed up as `SOUL.md.stock`). Timezone Africa/Casablanca set. **LIVE STATUS (2026-07-18):** Telegram + Discord (`Elmaati#1317`) both live, locked to operator IDs; home channel = operator Telegram DM (outbound verified via `hermes send`). Atelier: profiles `analyst` (gemini-3.5-flash), `scout` + `coder` (gpt-5.5), kanban board validated end-to-end. **Shop rule from smoke test: gemini-flash fails the kanban completion protocol (4/4) — kanban contracts only on protocol-reliable models (gpt-5.5 now; NIM qwen3.5-397b when key lands); flash is for interactive analysis only.** Avatar: `branding/elmaati-avatar-768.png`.

**Codex OAuth LIVE (2026-07-18):** `hermes auth add openai-codex` device-flow completed; provider `openai-codex`, model `gpt-5.5` (the `-codex` model variants are rejected on ChatGPT-account auth), verified end-to-end and set as `model.default`/`model.provider`. Inference-only — tools stay Hermes's own; confirm-gate posture unchanged. ToS caveat: subscription OAuth through a third-party daemon is gray territory (operator-accepted). `OPENROUTER_API_KEY` + `GOOGLE_API_KEY` found present in `~/.hermes/.env` (unverified). **Still pending:** Telegram bot token → gateway install; verify OpenRouter key; NVIDIA (`NVIDIA_API_KEY`) + Cloudflare (named custom provider) keys → casting order (Cloudflare → NVIDIA → OpenRouter cheap → gpt-5.5/escalation); Claude OAuth (`hermes auth add anthropic --type oauth`) deferred — shares the Pro sub with n8n's claude-code node; cron jobs; memory bridge.
**Decision drawer:** MemPalace `hq-decisions/voice-jarvis` — "Elmaati gets a body: Hermes Agent on server-architect (2026-07-17)"

Give the Maâllem persona a persistent body: [Hermes Agent](https://hermes-agent.org/) (Nous Research, MIT, Feb 2026) running as a daemon on server-architect under a dedicated `elmaati` Linux user. Text-mode Elmaati on Telegram/WhatsApp; the Gemini native-audio voice layer (`server/` in this repo) stays separate and can front the same brain later.

## Principles (non-negotiable)

1. **Least privilege by construction.** `elmaati` user has NO sudo, NO docker group, no access to `architect`'s home, keys, or the 62-secret `~/.n8n/.env` blob. This follows the ratified M4-hybrid isolation model (per-project Linux users) and mechanically enforces GLOBAL RULE #0 — Elmaati *cannot* edit deploy clones on the server.
2. **Conduct by delegation.** Elmaati executes only through scoped channels: n8n webhooks, read APIs, dispatch to existing agents. Confirm-gate: he proposes on Telegram/WhatsApp → operator approves → he fires the webhook. Never shell power.
3. **MemPalace stays canonical.** `~elmaati/.hermes/` memory is operational scratch only. Anything durable flows to MemPalace via the nightly bridge (below). No third palace.
4. **Own credentials.** Separate n8n API key, own OpenRouter key, own Telegram bot token — revocable without rotating real keys.

## Phase 1 — User + install (≈30 min, as root/architect via SSH)

```bash
# 1. Dedicated user, no password login, no sudo
adduser elmaati --disabled-password --gecos "Elmaati agent (Hermes)"

# 2. Install Hermes as elmaati (official curl installer; installs Python 3.11 via uv,
#    Node.js, ripgrep, ffmpeg; repo → ~/.hermes/hermes-agent/, command → ~/.local/bin/hermes)
sudo -u elmaati -i bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash'
```

Resource note: Contabo VPS is 6 vCPU / 12 GB with n8n, dashboard-v2, Postgres, Adolia Odoo already resident. Hermes daemon itself is light (Python; models are remote via OpenRouter). Set a memory ceiling in the systemd unit; do NOT run local vLLM on this box.

## Phase 2 — Services (REVISED after install discovery)

Discovery (v0.18.2): `hermes serve` defaults to `127.0.0.1:9119` and a non-loopback bind force-requires auth (June 2026 hardening). Hermes ships `hermes gateway install` which installs its own systemd service for messaging + cron. **Revised approach: run everything under elmaati's USER systemd manager** — no root-owned unit, sudo needed only for `loginctl enable-linger elmaati` (boot persistence) and `apt install ripgrep`. Hardening/limits (`MemoryMax=1500M`, `NoNewPrivileges`) go in the user units via drop-ins. The original root-unit design below is kept for reference only.

## Phase 2 (original design — superseded, reference only)

`/etc/systemd/system/elmaati.service` (system service, not user session, so it survives reboots without lingering):

```ini
[Unit]
Description=Elmaati (Hermes Agent daemon)
After=network-online.target

[Service]
User=elmaati
Group=elmaati
ExecStart=/home/elmaati/.local/bin/hermes serve     # loopback-only; verify flag for bind address
Restart=on-failure
RestartSec=10
# Hardening
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=tmpfs
BindPaths=/home/elmaati
PrivateTmp=yes
MemoryMax=1500M
CPUQuota=150%

[Install]
WantedBy=multi-user.target
```

Verify the real entrypoint path after install before enabling. `systemctl enable --now elmaati`.

**Desktop cockpit (Hermes Desktop on the Mac):** the daemon runs `hermes serve` bound to **loopback only** — never a public interface. The Mac's Hermes Desktop app reaches it through an SSH tunnel (`ssh -N -L 3779:127.0.0.1:3779 architect@84.247.138.95`, adjust to the real serve port) with Settings → Gateway → Remote gateway pointed at `http://127.0.0.1:3779`. No new open port, no OAuth surface on the brain box. Keep a separate desktop *profile* for the remote Elmaati so a local scratch Hermes never shares his state.

## Phase 3 — Config + persona

- **LLM providers (three endpoints, all OpenAI-compatible, all with keys created FOR Elmaati):**

  | Provider | Endpoint | Role |
  |---|---|---|
  | OpenRouter | `openrouter.ai/api/v1` | Default + breadth (200+ models), escalation tier |
  | Cloudflare Workers AI | `api.cloudflare.com/client/v4/accounts/{acct}/ai/v1` | Near-free tier for routine cron work (classify, summarize, watchdog verdicts) — account already exists (DNS is on Cloudflare) |
  | NVIDIA NIM | `integrate.api.nvidia.com/v1` | Free hosted big open models — the Darija bake-off candidates (122b-a10b, 397b-a17b, qwen3-next) live here; key already obtained 2026-06 |

  Casting order for cron jobs: Cloudflare → NVIDIA → OpenRouter cheap → OpenRouter escalation. Option B (later): point Hermes at ai-router's OpenAI-compatible endpoint so casting policy lives in ai-router instead of Hermes config.
- **Worker CLIs (Claude Code CLI, Codex CLI) — delegation targets, NOT providers.** They are executor agents with their own shell access, so during the pilot they are NOT installed under the `elmaati` user. Elmaati dispatches heavy/coding work to them through the existing channel: n8n webhook → `n8n-nodes-claude-code-cli` community node (already running on this server under the Claude Pro sub), behind the confirm-gate like any action webhook. A Codex equivalent gets the same webhook treatment if/when wired into n8n. Direct CLI installs under `elmaati` (own auth, scoped workspace) are a post-pilot decision — an autonomous daemon invoking an auto-approving CLI agent is two layers of unsupervised execution and needs its own review.
- **Persona:** system prompt = the Maâllem spec. Source of truth stays local at `core/elmaati/agents/elmaati-live.md`; deliver to server via scp (scp-verify hook covers this) into `~elmaati/.hermes/` config. Strip the voice-delivery directives (Algenib/audio) — this is the text surface. Baseline greeting stays: «السلام. أنا المعطي. شنو خدّامين عليه؟»
- **Messaging:** Telegram first (create bot via @BotFather, token owned by Elmaati). WhatsApp gateway only after the 2-week pilot passes.

## Phase 4 — First two cron jobs

1. **n8n execution watchdog** (every 30 min): scoped n8n API key (created fresh, read-only if the n8n version supports scopes) → list recent executions → alert on Telegram ONLY on failures/stalls in the reel pipeline + support workflows.
2. **Morning briefing** (07:30 Africa/Casablanca): overnight n8n executions, dashboard-v2 health (HTTP check on localhost), receptionist call count, Adolia ads snapshot via existing n8n webhook. One message, Maâllem register: economical, decisive.

## Phase 5 — Memory bridge (no third palace)

Nightly cron: Elmaati writes a one-block operational summary (what he observed, what he alerted, what changed) to a drop path the daybook scribe (`tools/daybook/scripts/daily_scribe.py`) ingests, so his day lands in the `daybook` wing like every other agent. `~/.hermes/` is never mined directly.

## Pilot gates (2 weeks)

- Alerts are trustworthy (no cry-wolf, no missed reel-pipeline failures).
- Cost stays negligible on OpenRouter cheap models.
- No writes outside `~elmaati` (spot-check).

**Pass →** add WhatsApp gateway, grant first *action* webhook (confirm-gated), consider ai-router casting.
**Fail →** disable service, wipe `~elmaati`, zero blast radius.

## Explicitly out of scope

- Voice (Gemini native-audio server in this repo) — unchanged, separate surface.
- Any self-written Hermes skill that executes with credentials — skills audit required before granting action webhooks.
- Docker socket access — if container status is ever needed, use a read-only socket proxy (tecnativa/docker-socket-proxy), never docker-group membership.
