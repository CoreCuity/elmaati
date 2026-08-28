# ELMAATI OS — the clean-build operating picture

**v2 — 2026-07-18.** Supersedes v1 of this doc (same day): v1 assumed incremental cleanup of `architect`; the operator's call is **strangler, not renovation**. Companion to `HERMES-DEPLOY.md` (the body) and `agents/elmaati-soul.md` (the identity).

## The strategic frame

- **`architect` + the current HQ wiring are TEST BEDS.** They proved the ideas; they are not the product.
- **Slated for replacement or deletion: n8n, dashboard-v2, content-engine** (in their current forms). No de-comingling of `~/.n8n/.env`, no decomposition of `architect` — legacy is frozen, run-until-replaced, then deleted. Dead code doesn't get refactored.
- **The retired principle:** "n8n workflows own orchestration" served the test bed. In Elmaati OS, **orchestration is Hermes-native**: kanban (order book) + profiles (workers) + cron (schedule) + skills (craft). The keeper-principle survives translated: *"Elmaati owns orchestration. The atelier owns intelligence."*
- **The product focus is the AI Receptionist** (`products/ai-receptionist/`, ship/v1). Elmaati OS's first job is running it well.

## The three planes (v2)

```
┌─ ELMAATI OS ─ user: elmaati (+ svc-* when warranted) ──────┐
│ Hermes: Telegram/WhatsApp/desktop · SOUL · confirm-gate     │
│ ATELIER (hybrid): profiles+kanban+dispatcher in-daemon;     │
│   svc-* Linux users ONLY for client-secret / untrusted      │
│   workloads as they are built (receptionist tenants ⇒ yes)  │
│ Casting: Cloudflare → NVIDIA → OpenRouter → gpt-5.5(Codex)  │
└──────────────┬─────────────────────────────────────────────┘
               │ scoped APIs · dispatch · registered channels
┌─ LEGACY PLANE ─ user: architect (frozen test bed) ─────────┐
│ n8n · dashboard-v2 · content-engine: run-until-replaced.    │
│ NO new work lands here. Read-only monitoring from above.    │
│ Each capability rebuilt clean in Elmaati OS ⇒ legacy        │
│ counterpart deleted (decommission log below).               │
└──────────────┬─────────────────────────────────────────────┘
               │ edit locally → commit → push → pull (RULE #0)
┌─ KNOWLEDGE PLANE ─ local HQ + MemPalace (unchanged) ───────┐
│ HQ repo: source of truth for code/personas/this doc         │
│ MemPalace: canonical memory · daybook: what happened        │
│ ~elmaati/.hermes = operational scratch, bridged nightly     │
└─────────────────────────────────────────────────────────────┘
```

OS thesis (unchanged): **Elmaati is the interface to the machine, not the machine.** Capabilities arrive as channels — registered, scoped, confirm-gated — never as privilege.

## Build order

### 1 — Receptionist ops (NOW — the main focus)
The first real capability in Elmaati OS, built Hermes-native from day one:
- [ ] **Repo first**: `ai-receptionist` on `ship/v1` has uncommitted local edits (`.env.example`, `agents.json` — noted 2026-07-09). Reconcile and commit before anything builds on it.
- [ ] **Ops watch**: Elmaati monitors receptionist health + call outcomes (read-only channel) and reports in the morning briefing; call-review on demand from Telegram.
- [ ] **Atelier workers**: `receptionist-analyst` profile (call transcript review, booking-funnel report) on a cheap casting lane.
- [ ] **Tenant isolation rule (the Hybrid decision applied)**: anything holding a *tenant's* live credentials (Désirs, spa clients) runs under a `svc-receptionist` Linux user, not inside the elmaati daemon. The atelier analyzes; the svc user operates.
- [ ] Per-tenant onboarding becomes a kanban template Elmaati can `decompose` and drive.

### 2 — Watchtower over legacy (cheap, parallel)
Read-only crons watching the frozen test bed while it still serves: process/disk/service health of n8n·dashboard·content-engine hosts + 07:30 briefing. No scoped n8n API key project anymore — plain HTTP/systemd checks suffice for a plane that's dying.

### 3 — Replacement builds (each one strangles a legacy service)
- [ ] **Dashboard-v2 →** Elmaati IS the dashboard first (ask him instead of opening it); a thin Hermes-served status page later only if a screen is genuinely missed.
- [ ] **n8n flows →** re-expressed as Hermes cron + skills + kanban templates, only the flows that still matter post-content-engine.
- [ ] **Content-engine →** strategy decision pending (SignGazer pivot frozen on CE-26); whatever ships next is built as atelier work, not n8n graphs.
- [ ] **Decommission log**: every deletion recorded here + MemPalace drawer (what died, what replaced it, where its data went).

## Governance line (v2)
- **Najlaa** decides; her "yes" gates anything that writes, sends, deletes, or spends.
- **Elmaati** watches, reports, proposes; fires only *registered channels* after the yes; runs the atelier.
- **Atelier profiles** do the intelligent work; **svc-* users** hold tenant credentials and untrusted execution.
- **Legacy plane** accepts no new work, ever. It shrinks until it's gone.
- **HQ repo** = code truth · **MemPalace** = memory truth · **daybook** = what happened.
