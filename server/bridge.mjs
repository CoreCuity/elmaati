import dotenv from 'dotenv';
import { WebSocketServer, WebSocket } from 'ws';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { dirname, resolve, join } from 'node:path';
import { createDispatcher } from './lib/dispatcher.mjs';

// Keys live in .env.local (Next.js convention). dotenv/config only reads .env,
// so load .env.local explicitly, falling back to .env.
dotenv.config({ path: '.env.local' });
dotenv.config();

const GEMINI_URL =
  'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';
const API_KEY = process.env.GEMINI_API_KEY;

if (!API_KEY) {
  console.error('GEMINI_API_KEY must be set in .env.local (or .env).');
  process.exit(1);
}

const PORT = Number(process.env.BRIDGE_PORT) || 8081;
const __dirname = dirname(fileURLToPath(import.meta.url));     // core/elmaati/server
const REPO_ROOT = resolve(__dirname, '..', '..', '..');        // …/corecuity
const ROLES_PATH = join(REPO_ROOT, 'core', 'elmaati', 'roles.json');
const JOBS_LOG = join(__dirname, 'state', 'jobs.jsonl');
const SEARCH_SCRIPT = fileURLToPath(new URL('./mempalace_search.py', import.meta.url));

// ── Tool layer ────────────────────────────────────────────────────────────
// The bridge owns Elmaati's tools: it injects the declarations into the setup
// message and executes tool calls server-side. This is the governed boundary —
// the browser never touches the Palace or spawns workers; the maâllem does.
const ROLES = JSON.parse(readFileSync(ROLES_PATH, 'utf8')).roles ?? {};
const ROLE_NAMES = Object.keys(ROLES);
const ROLE_MENU = Object.entries(ROLES)
  .map(([k, v]) => `${k}: ${v.summary} (${v.access})`).join(' | ');

const TOOLS = [
  {
    functionDeclarations: [
      {
        name: 'mempalace_search',
        description:
          "Search the CoreCuity MemPalace — the company's long-term memory — for facts " +
          'about CoreCuity, its projects and clients (Adolia, LiveItMaghribi, Désirs ' +
          "d'Orient, SignGazer), competitors, people, infrastructure, and past decisions. " +
          "Call this whenever asked about anything specific to CoreCuity you don't already know.",
        parameters: {
          type: 'OBJECT',
          properties: { query: { type: 'STRING', description: 'Keywords or a short question.' } },
          required: ['query'],
        },
      },
      {
        name: 'delegate',
        description:
          'Hand a task to one of your workshop agents and get back a job that runs in the ' +
          'background — you receive its result as a later message and speak it then. Read-only ' +
          'roles run at once. Write roles (they change the environment) return needing the ' +
          "operator's spoken yes: tell her plainly what you're about to do, then call `confirm` " +
          'with the token. Roles — ' + ROLE_MENU,
        parameters: {
          type: 'OBJECT',
          properties: {
            role: { type: 'STRING', enum: ROLE_NAMES, description: 'Which workshop agent.' },
            task: { type: 'STRING', description: 'Plain-language brief for the worker — be specific.' },
          },
          required: ['role', 'task'],
        },
      },
      {
        name: 'confirm',
        description:
          'Approve or cancel a held write task after the operator has spoken her decision. ' +
          'Only call this once she has actually said yes or no — never decide for her.',
        parameters: {
          type: 'OBJECT',
          properties: {
            token: { type: 'STRING', description: 'The token from the delegate that needed confirmation.' },
            approved: { type: 'BOOLEAN', description: 'true if she said yes, false if she declined.' },
          },
          required: ['token', 'approved'],
        },
      },
    ],
  },
];

function runSearch(query) {
  return new Promise((resolve) => {
    const py = spawn('/usr/bin/python3', [SEARCH_SCRIPT, query]);
    let out = '', err = '';
    py.stdout.on('data', (d) => (out += d));
    py.stderr.on('data', (d) => (err += d));
    py.on('close', () => {
      try {
        const line = out.trim().split('\n').filter((l) => l.startsWith('{')).pop();
        resolve(JSON.parse(line));
      } catch { resolve({ results: [], error: (err || 'search failed').slice(0, 200) }); }
    });
    py.on('error', (e) => resolve({ results: [], error: String(e) }));
  });
}

// Feed text into the live session as a turn so Elmaati speaks it.
function speak(geminiWs, text) {
  if (geminiWs.readyState === WebSocket.OPEN) {
    geminiWs.send(JSON.stringify({
      clientContent: { turns: [{ role: 'user', parts: [{ text }] }], turnComplete: true },
    }));
  }
}

async function handleToolCall(toolCall, geminiWs, ctx) {
  const calls = toolCall.functionCalls || [];
  const responses = [];
  for (const c of calls) {
    const a = c.args || {};
    if (c.name === 'mempalace_search') {
      console.log(`[tool] mempalace_search("${a.query || ''}")`);
      const result = await runSearch(a.query || '');
      responses.push({ id: c.id, name: c.name, response: result });

    } else if (c.name === 'delegate') {
      const res = ctx.dispatcher.delegate({ role: a.role, task: a.task });
      console.log(`[tool] delegate(${a.role}) -> ${res.status ?? 'dispatched'} ${res.id ?? ''}`);
      if (res.status === 'needs_confirm') {
        const token = `c${Date.now()}`;
        ctx.pendingConfirms.set(token, { role: a.role, task: a.task });
        responses.push({ id: c.id, name: c.name, response: {
          status: 'needs_confirmation', token,
          note: `This writes to the environment. Tell her plainly what you're about to do and wait for her yes — then call confirm with token ${token}.` } });
      } else if (res.status === 'unknown_role' || res.status === 'bad_request') {
        responses.push({ id: c.id, name: c.name, response: { status: res.status, message: res.message } });
      } else {
        responses.push({ id: c.id, name: c.name, response: {
          status: 'dispatched', jobId: res.id, role: a.role,
          note: `Handed to the ${a.role}. Say so in one line and keep going — I'll bring the result when it's done.` } });
      }

    } else if (c.name === 'confirm') {
      const p = ctx.pendingConfirms.get(a.token);
      if (!p) {
        responses.push({ id: c.id, name: c.name, response: { status: 'no_such_pending' } });
      } else {
        ctx.pendingConfirms.delete(a.token);
        if (a.approved) {
          const job = ctx.dispatcher.delegate({ role: p.role, task: p.task, confirmed: true });
          console.log(`[tool] confirm -> approved, dispatched ${job.id} (${p.role})`);
          responses.push({ id: c.id, name: c.name, response: { status: 'dispatched', jobId: job.id, role: p.role } });
        } else {
          console.log(`[tool] confirm -> cancelled (${p.role})`);
          responses.push({ id: c.id, name: c.name, response: { status: 'cancelled', role: p.role } });
        }
      }

    } else {
      responses.push({ id: c.id, name: c.name, response: { error: 'unknown tool' } });
    }
  }
  if (responses.length && geminiWs.readyState === WebSocket.OPEN) {
    geminiWs.send(JSON.stringify({ toolResponse: { functionResponses: responses } }));
  }
}

function transformClientMessage(text) {
  let msg;
  try { msg = JSON.parse(text); } catch { return text; }
  if (msg.setup) { msg.setup.tools = TOOLS; return JSON.stringify(msg); }
  return text;
}

const wss = new WebSocketServer({ port: PORT });

wss.on('connection', async (clientWs) => {
  console.log('Client connected to bridge');
  const geminiWs = new WebSocket(`${GEMINI_URL}?key=${API_KEY}`);

  // Per-connection workshop: the maâllem's atelier. Job results are spoken back
  // into THIS session when they finish.
  const pendingConfirms = new Map();
  const dispatcher = await createDispatcher({
    repoRoot: REPO_ROOT,
    rolesPath: ROLES_PATH,
    jobsLog: JOBS_LOG,
    onEvent: (ev) => {
      if (ev.type !== 'done' && ev.type !== 'failed') return;
      const j = ev.job;
      speak(geminiWs, j.status === 'done'
        ? `The ${j.role} finished ${j.id}. Result: ${j.result || '(empty)'}`
        : `The ${j.role} failed ${j.id}. ${j.error || j.result || ''}`);
    },
  });
  const ctx = { dispatcher, pendingConfirms };

  const pending = [];
  let geminiOpen = false;

  // DEBUG: log the top-level key of each message we forward upstream.
  const logFwd = (text) => { try { console.log(`[fwd] ${Object.keys(JSON.parse(text))[0]}`); } catch {} };

  clientWs.on('message', (data) => {
    const text = transformClientMessage(data.toString());
    if (geminiOpen && geminiWs.readyState === WebSocket.OPEN) { logFwd(text); geminiWs.send(text); }
    else pending.push(text);
  });

  geminiWs.on('open', () => {
    console.log('Connected to Gemini Live');
    geminiOpen = true;
    for (const msg of pending) { logFwd(msg); geminiWs.send(msg); }
    pending.length = 0;
  });

  geminiWs.on('message', (data) => {
    const text = data.toString();
    if (clientWs.readyState === WebSocket.OPEN) clientWs.send(text);
    let msg;
    try { msg = JSON.parse(text); } catch { return; }
    if (msg.toolCall) handleToolCall(msg.toolCall, geminiWs, ctx);
  });

  geminiWs.on('close', (code, reason) => {
    console.log(`Gemini Live disconnected. code=${code} reason=${reason?.toString() || ''}`);
    if (clientWs.readyState === WebSocket.OPEN) clientWs.close();
  });
  geminiWs.on('error', (err) => {
    console.error('Gemini Live error:', err?.message || err);
    if (clientWs.readyState === WebSocket.OPEN) clientWs.close();
  });
  clientWs.on('close', () => {
    console.log('Client disconnected');
    if (geminiWs.readyState === WebSocket.OPEN || geminiWs.readyState === WebSocket.CONNECTING) geminiWs.close();
  });
});

console.log(`WebSocket bridge running on ws://localhost:${PORT}`);
console.log(`  workshop roles: ${ROLE_NAMES.join(', ')}`);
