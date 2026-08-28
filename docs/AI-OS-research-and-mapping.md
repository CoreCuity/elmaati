# Elmaati & CoreCuity as an AI OS — Research + Architecture Mapping

> Compiled 2026-05-26 from a 4-stream web research fan-out (AI-OS architecture · realtime voice · orchestration/memory/MCP · competitive landscape). Sources at the end of each section. **Caveat:** specific model slugs/dates (Gemini Live model names, OpenAI `gpt-realtime-2`, funding figures) come from post-Jan-2026 web research — treat the *structural* advice as solid and **verify exact model names against Google's live deprecations page before wiring**.

---

## TL;DR — six things that matter

1. **CoreCuity has already built ~80% of an "AI OS."** ai-router (kernel/scheduler), MemPalace (memory hierarchy), n8n (orchestration), the subagent team (processes), Odoo (system of record), MCP (partial syscall layer). This is not a coincidence to discover — it's a position to exploit.
2. **Elmaati is not a new app. It's the missing *shell* of an OS you already have.** The kernel (ai-router) + memory (MemPalace) + syscalls (n8n/MCP) exist. Elmaati is the voice-native HCI layer that finally lets a human *drive* the kernel. Reframing it this way changes what you build.
3. **The Gemini Live 404 is a 3-part fix:** `gemini-2.0-flash-exp` is retired → use a current Live model; use the `v1beta` endpoint with `&alt=ws`; and move the WebSocket **server-side** (browser must not connect to Gemini directly). There's already a working Discord+Gemini-Live bot on the server — extend that pattern, don't reinvent.
4. **MCP is the unification play.** Expose n8n + MemPalace as MCP servers; let *both* Elmaati (voice) and Claude (text) consume the identical tool surface. This enforces "external APIs through n8n" at the protocol level and means one new workflow = a new capability for every interface at once.
5. **The 5 real gaps, ranked: (1) access control [MISSING, multi-tenant risk], (2) unified tool ABI via MCP [partial], (3) in-context memory blocks [missing], (4) memory consolidation episode→KG [missing], (5) unified perception/event bus [missing].** Everything else is "augment," not "build."
6. **Strategically: drop the "AI OS" label externally, pick ONE vertical (Booking), and build the Darija data moat.** "AI OS" is category noise / "agent-washing." The defensible asset Odoo v20 cannot buy is *proprietary Darija operational data* — and every Elmaati turn generates it.

---

## 1. The canonical AI-OS layer model

Synthesized from Karpathy's "LLM OS," the academic **AIOS** kernel (agiresearch, COLM 2025), **MemGPT/Letta**, and the 2026 agent-runtime landscape. The recurring primitives:

| # | Layer | Responsibility | OS analogy |
|---|-------|----------------|-----------|
| 0 | **Model substrate** | Raw inference; frozen weights | CPU + ROM/firmware |
| 1 | **Kernel / LLM core** | Reasoning loop; dispatch; model abstraction | Kernel process + CPU |
| 2 | **Scheduler** | Concurrency, queuing, prioritization, context-switch | Process scheduler |
| 3 | **Memory hierarchy** | Manage finite context: core (RAM) ↔ recall (swap) ↔ archival (disk); self-editing | Virtual memory + paging |
| 4 | **Tool / syscall layer** | Sandboxed external capabilities (web, code, APIs, DB) | Syscalls + drivers (**= MCP**) |
| 5 | **Storage / persistence** | Durable state; files, vector index, records | Filesystem + block device |
| 6 | **Perception / interface** | Translate world↔tokens; multimodal I/O | I/O subsystem |
| 7 | **Access control** | Per-agent/tenant privileges; gate irreversible actions | Privilege rings + ACL |
| 8 | **Agents as processes** | User-space programs; goals, scoped memory, fork/IPC | Processes + IPC |
| 9 | **Orchestration runtime** | Multi-agent topology, lifecycle, observability | init / systemd |

Karpathy's mapping in one line: **LLM = CPU/kernel · context window = RAM · vector DB/files = disk · tools/browser = peripherals · other LLMs = processes · prompt loop = shell.**

The two reference implementations worth knowing:
- **AIOS** (arXiv:2403.16971) — an explicit kernel: LLM core, agent scheduler, context manager, memory manager, storage manager, **tool manager (now MCP-backed)**, **access manager**. ~2.1× throughput on concurrent agents.
- **Letta / MemGPT** (arXiv:2310.08560) — the canonical *memory* model: always-in-context **core blocks** (persona + human/user model), **recall** (evicted-but-searchable), **archival** (vector/graph), with the agent issuing its own `memory_write` syscalls.

Sources: [Karpathy LLM OS](https://x.com/karpathy/status/1723140519554105733) · [AIOS](https://github.com/agiresearch/AIOS) · [arXiv:2403.16971](https://arxiv.org/html/2403.16971v5) · [Letta](https://docs.letta.com/core-concepts/) · [MemGPT arXiv:2310.08560](https://arxiv.org/pdf/2310.08560)

---

## 2. CoreCuity mapped onto the AI-OS layers (the centerpiece)

| Layer | CoreCuity component | Status | Verdict |
|-------|---------------------|--------|---------|
| 0 Model substrate | ai-router providers (Claude+Gemini+Codex, cost-tiered) | ✅ **Strong** | Keep |
| 1 Kernel | ai-router + Elmaati as the voice surface of the kernel | 🟡 Kernel strong; Elmaati prototype | Promote Elmaati |
| 2 Scheduler | n8n (workflow scheduling) | 🟡 **Partial** | n8n schedules *flows*, not concurrent LLM requests; OK for now |
| 3 Memory | MemPalace (vector + temporal KG, wings/rooms/drawers) | ✅ **Advanced** | Augment (see §4) |
| 4 Tool/syscall | MCP (MemPalace already MCP-exposed) | 🟡 **Partial** | **Unify via MCP** (see §6) |
| 5 Storage | MemPalace (AI-native) + Odoo (system of record) | ✅ Present | Add a routing abstraction |
| 6 Perception | Elmaati (voice) + WhatsApp + Discord + The Hub | 🟡 Distributed | Add event bus |
| 7 **Access control** | — | ❌ **MISSING** | **Build first** |
| 8 Agents-as-processes | subagent team (scriptwriter, scout, strategist, maintainers) | ✅ Present | Add lifecycle/scope |
| 9 Orchestration | n8n ("n8n owns orchestration") | ✅ **Strong** | Keep + MCP-expose |

**The headline:** the expensive, hard layers (kernel, memory, orchestration, model fallback) are *done and ahead of market*. ai-router's agent-semantic routing (route by declared `quality`/`latency`/`cost` + failure-bucket fallback) is **more sophisticated than commercial gateways** (OpenRouter/LiteLLM/Portkey route by model/cost, not by agent capability). MemPalace's vector + **temporal KG** matches Zep/Graphiti, the SOTA memory system — and it already does **hybrid retrieval** (the live search returns `bm25_score` + vector distance + a "closet" graph boost), which most agent frameworks lack. You are not behind on architecture. You are behind on the *connective tissue* (layers 4, 6, 7).

---

## 3. The 5 gaps that actually matter (ranked)

**Gap 1 — Access control (Layer 7). MISSING. Highest priority.**
For a multi-tenant SME platform, the single dangerous truth: any agent can today read any MemPalace drawer, write to any Odoo, and there's no gate on irreversible actions (financial ops, contact deletion, WhatsApp blasts). This is a security *and* regulatory *and* client-trust risk. Fix: per-agent/per-tenant privilege table (in MemPalace metadata), MCP tool calls gated by caller identity, and a human-in-the-loop confirm hook on the "write/destructive" tool tier already named in the Elmaati persona spec (`reel_init`, `whatsapp_send`, `mempalace_diary_write`, `workflow_trigger`).

**Gap 2 — Unified tool ABI via MCP (Layer 4). PARTIAL.**
Tool surfaces are fragmented per interface. Make n8n + MemPalace MCP servers the *single* tool surface for both voice and text (see §6). This is the highest-leverage structural move.

**Gap 3 — In-context core memory blocks (Layer 3). MISSING.**
Today each agent rebuilds context ad hoc via MemPalace search. Elmaati's "knows everything" promise is only as consistent as the search hit. Adopt Letta's pattern: a standardized always-loaded block injected at session start — `persona` (Elmaati's spec), `tenant` (which client), `human` (which user), `objectives`. MemPalace already holds all of this; formalize the load.

**Gap 4 — Memory consolidation: episode → KG fact. MISSING.**
The daybook (`daily_scribe.py`, just repaired this session) now does *episodic* logging. Nothing yet promotes those episodes into *semantic* KG triples. Add a nightly consolidation sub-agent (n8n scheduled → ai-router agent) that reads the day's diary + transcripts, extracts entities/relationships, and writes them back via `mempalace_kg_add` — with conflict detection (`superseded_at` on contradicting edges). This is also the **Darija data pipeline** (Gap → moat; see §7).

**Gap 5 — Unified perception / event bus (Layer 6). MISSING.**
WhatsApp, Discord, voice, and Hub inputs run separate pipelines. Route them all through one n8n "perception gateway" → ai-router dispatch, so every channel inherits the same memory, tools, and access control.

Everything else (scheduler, hybrid retrieval, model catalog) is **augment**, not build.

---

## 4. ai-router & MemPalace verdicts

**ai-router → KEEP + augment.** Genuinely ahead of gateways on agent-semantic routing and failure-semantic fallback (separate `generic`/`content_policy`/`context_window` buckets + 80% quota knee). Augment with: (a) **prompt caching** for stable system prompts, (b) **semantic response caching** for idempotent tool calls, (c) optionally slot **LiteLLM underneath** as the provider-adapter shim (100+ providers) while ai-router keeps the semantic routing on top — kills duplicate adapter code. Map Elmaati's persona rule ("name models by role: *the fast model*, *the strategist*") directly onto ai-router agent selection.

**MemPalace → AUGMENT (it's close to SOTA).** It already has vector + temporal KG + hybrid (BM25+vector+graph) retrieval — ahead of most. Add: (1) memory **consolidation** cron (Gap 4); (2) **procedural** memory tier (a `procedures` room — "how to do X", retrieved by task type); (3) **staleness/conflict** handling on KG writes; (4) **strict multi-tenant isolation** enforced at the MCP layer, not by naming convention (ties to Gap 1).

Sources: [Best LLM Gateways 2026](https://www.braintrust.dev/articles/best-llm-gateways-2026) · [Zep/Graphiti](https://www.getzep.com/) · [Mem0 graph memory](https://mem0.ai/blog/graph-memory-solutions-ai-agents) · [Anthropic multi-agent system](https://www.anthropic.com/engineering/multi-agent-research-system)

---

## 5. Elmaati voice architecture

### 5.1 The Gemini Live 404 — fix
Three causes, all present in the current prototype:
1. **Retired model.** `gemini-2.0-flash-exp` was an experimental alias, never a stable Live slot; the 2.0 Live model was shut down. **Use a current Live model** — per research, either `gemini-2.5-flash-native-audio-preview-12-2025` (native audio, **async/NON_BLOCKING tool calls** — best for Elmaati) or `gemini-3.1-flash-live-preview` (lower latency, sync tools). ⚠️ **Verify the exact slug** on [ai.google.dev deprecations](https://ai.google.dev/gemini-api/docs/deprecations) — these names churn.
2. **Endpoint/version.** Use `v1beta` with the `&alt=ws` query param:
   `wss://generativelanguage.googleapis.com/v1beta/models/{MODEL}:BidiGenerateContent?key={KEY}&alt=ws`
3. **Topology.** The browser must **not** open the Gemini socket directly. Put the WS in a **server-side agent** (this also eliminates the port collision). The existing `discord-voice-node` service (@discordjs/voice + Gemini Live, live on server-architect) is the working precedent.

Audio: in = 16-bit PCM @16 kHz; out = 24 kHz. Session limit ~15 min (audio) → use `sessionResumption` for longer.

### 5.2 Recommended architecture
**v0 (ship in ~1–2 weeks):** Next.js → **LiveKit room (WebRTC)** → Python/Node **LiveKit Agent** → **Gemini native-audio Live** → **n8n webhook tools (via MCP)**.
- LiveKit gives you VAD, barge-in, turn detection, session resumption for free, and WebRTC means the browser connects to the *room*, not Gemini — port collision gone.
- **Async tool calls are essential**: they map exactly to the persona spec's "I need to check the Palace" — Elmaati can speak the filler line while the n8n tool resolves, instead of freezing.
- Trilingual system prompt; native-audio auto-detects EN/FR/Darija per utterance. No language pre-pass.

**v2 (4–8 weeks):** stable model when GA; **ElevenLabs Darija voice** ("GHIZLANE") or a cloned "Elmaati" voice via output voice-conversion (~+200 ms); MemPalace core-block injection per session; MCP sidecar so the *same* tools serve voice + Claude; Darija STT fallback (`speechbrain/asr-wav2vec2-dvoice-darija`) for heavy-dialect/Amazigh-loanword cases.

### 5.3 Companion-hardware lessons (Rabbit R1, Humane, Friend, Limitless — all failed)
- **Own the API surface** — never screen-scrape apps (R1's "LAM" failure). Elmaati's n8n-webhook design is already correct.
- **Invocable, not ambient** — give a clear trigger (the Vessel tap / hotword); always-on listening creates anxiety, not value.
- **Attach to existing surfaces** — WhatsApp/Discord, not a new device. (Already the plan.)
- **Speech-to-speech is table stakes** — cascaded STT→LLM→TTS (2–4 s latency) feels broken in 2026.
- **Earn the "better than my phone" test** — Elmaati's only durable edge is *deep ERP/n8n/MemPalace access no generic assistant has*. Surface that in the first 30 seconds.

Sources: [Gemini Live WS guide](https://ai.google.dev/gemini-api/docs/live-api/get-started-websocket) · [Live API ref](https://ai.google.dev/api/live) · [LiveKit Agents](https://docs.livekit.io/agents/) · [Pipecat](https://github.com/pipecat-ai/pipecat) · [ElevenLabs Darija voice](https://elevenlabs.io/) · [DVoice Darija ASR](https://huggingface.co/speechbrain/asr-wav2vec2-dvoice-darija) · [OpenAI Realtime](https://platform.openai.com/docs/guides/realtime)

---

## 6. MCP — the unifying tool ABI

Voice agents calling MCP tools is **production-ready in 2026** (OpenAI Realtime consumes remote MCP natively; any voice runtime can). Target shape:

```
Elmaati voice runtime (LiveKit + Gemini native-audio)        Claude (text agents, hooks, subagents)
            │  MCP client (Streamable HTTP, OAuth 2.1)                    │  MCP client
            └───────────────┬─────────────────────────────────┬─────────┘
                            ▼                                   ▼
                  n8n MCP server                       MemPalace MCP server (exists)
          (MCP Server Trigger nodes wrapping            mempalace_search
           every webhook; auth + rate-limit +           mempalace_kg_query
           input validation at the protocol)            mempalace_diary_write
           send_whatsapp · pipeline_snapshot
           reel_init · dashboard_query · workflow_trigger
```

Why: **one tool surface for all callers** — add an n8n workflow once, both voice and text get it. n8n becomes the *governed* tool layer (auth/rate-limit/validation before any real API), enforcing "external APIs through n8n" at the protocol level. **Voice latency rule:** tools must resolve <~20 s — design n8n MCP tools to return a job-id immediately for long ops + a polling tool, rather than blocking the audio stream. This is also where **access control (Gap 1)** lands naturally — gate per-tool by caller identity at the MCP server.

Sources: [MCP architecture](https://modelcontextprotocol.io/docs/learn/architecture) · [OpenAI voice agents + MCP](https://openai.github.io/openai-agents-js/guides/voice-agents/) · [n8n as MCP hub](https://www.infralovers.com/blog/2026-03-09-n8n-agentic-mcp-hub/)

---

## 7. Strategy — honest version

- **Drop "AI OS" externally.** It's category noise ("agent-washing"; Gartner: ~130 of thousands of "agent" vendors are genuinely agentic; NBER: ~90% of firms report zero measurable AI productivity gain). Lead with a concrete vertical outcome.
- **Pick ONE vertical: Booking (spa/hotel/clinic).** Highest Morocco density, WhatsApp booking is immediately legible, and it maps to the existing `spa-receptionist` work + Désirs d'Orient. Ship a documented **3-client case study** ("automated 80% of WhatsApp bookings, cut no-shows 40%") *before* the UM6P Explorer Fall 2026 application. Vertical depth is where value accrues (Rebar: $14M Series A owning one workflow).
- **Build the Darija data moat — the one thing Odoo v20 can't buy.** Every Elmaati/WhatsApp turn → labeled Moroccan-SME conversation data → fine-tune a self-hostable model (data-sovereignty angle). Gap 4 (memory consolidation) *is* this pipeline. Make instrumentation a first-class requirement now.
- **Position ABOVE Odoo, not around it.** Biggest existential threat = Odoo commoditizing the agent layer (native AI in 18/19; gap closes by 20–21). Your value is the *orchestration intelligence above Odoo* (n8n spanning Odoo+WhatsApp+voice+APIs, vertical logic, the owner's dashboard). Frame Odoo as infrastructure/partner. Don't compete on "Odoo+chatbot."
- **Scope Elmaati honestly.** "A single persona runs your whole business" is a deck claim that dies in year one. "A named persona as the *interface* to bounded automations (booking, follow-up, order status, invoice query) in Darija/FR/EN across voice + WhatsApp" is a *real* wedge (Sierra, Synthflow validate it). The existing persona spec already says "WhatsApp is one channel" — hold that line.
- **Local competitors are closer than they look:** SAWT IA / Sensei Prod (Darija voice + CRM/ERP), Hunter BI & Bots Factory & Smartly.ma (Darija WhatsApp). None has the *end-to-end* stack — that's the edge, but the window is 12–18 months.
- **Meta's WhatsApp ban (Jan 2026) is a tailwind:** it kills generic chatbots but permits task-specific business agents. Elmaati is task-specific by design — market it that way; pursue official WhatsApp Business API partner status.

Sources: [Menlo vertical-AI thesis](https://menlovc.com/perspective/software-finally-gets-to-work-the-opportunity-in-vertical-ai/) · [Rebar $14M](https://venturebeat.com/business/rebar-closes-14m-series-a-led-by-prudence-to-rapidly-scale-its-ai-platform-for-hvac-electrical-and-plumbing-industries/) · [Odoo AI pricing](https://www.braincuber.com/blog/odoo-ai-modules-full-feature-list-and-pricing) · [WhatsApp 2026 AI policy](https://respond.io/blog/whatsapp-general-purpose-chatbots-ban) · [Sensei Prod SAWT IA](https://en.7news.ma/sensei-prod-unveils-sawt-ia-the-first-voice-ai-in-moroccan-arabic/) · [Hunter BI Morocco](https://hunterbi.com/ai-adoption-morocco-2025-smes/)

---

## 8. Sequenced roadmap

**Now (Elmaati unblock):**
1. Fix Gemini Live: current model slug + `v1beta&alt=ws` + server-side socket. Prove one voice round-trip.
2. Stand up v0: LiveKit + Gemini native-audio; one n8n tool wired (`mempalace_search`) so Elmaati can answer "what do we know about X."

**Next (connective tissue):**
3. **MCP unification** — n8n MCP server + confirm MemPalace MCP; point both Elmaati and Claude at it.
4. **Access control v1** — per-tenant/agent privilege gate on MCP tools + confirm-hook on destructive tier.
5. **Core memory blocks** — session-start injection of persona/tenant/user from MemPalace.

**Then (moat):**
6. **Memory consolidation cron** (episode→KG) = the Darija data pipeline.
7. **Booking vertical** 3-client case study for UM6P Explorer.

**Decisions needed from you:**
- Voice runtime: **LiveKit (recommended)** vs raw WS vs reuse the Discord-voice pattern as the server?
- Branded voice in v0 (Gemini default) vs hold for v2 (ElevenLabs Darija/clone)?
- Do we make MCP the mandated tool ABI now, or ship Elmaati v0 on direct n8n webhooks first and migrate?
