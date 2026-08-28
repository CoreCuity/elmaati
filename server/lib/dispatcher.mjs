// lib/dispatcher.mjs — the delegate engine. THIS is the extracted concept.
//
// The conductor (Gemini Live) never does work and never names a model. It emits
// one tool call: delegate({ role, task }). This engine turns that into an
// ai-router invocation, runs it ASYNC (so a 3-minute job never freezes a
// sub-second conversation), tracks it in a job table, and fires a callback when
// it's done so the conductor can speak the result.
//
// Two worker kinds (see roles.json):
//   cli   -> `ai-router <provider> --target=<repo> -- <args>`  (env-aware claude)
//   agent -> `ai-router --agent=<name> --agents-dir=... --prompt-file=...` (thin)
//
// Safety:
//   - access:'write' roles are NOT spawned until delegate() is called with
//     { confirmed:true }. The conductor must get a spoken "yes" first.
//   - access:'write' + weight:'heavy' jobs are SERIALIZED (one writer at a
//     time) because HQ is not a git repo — parallel writers collide on files.
//   - file-write blast radius is independently capped by the in-repo
//     isolation-guard hook, which fires inside every spawned claude worker.

import { spawn } from 'node:child_process';
import { readFile, writeFile, mkdir, appendFile } from 'node:fs/promises';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ORACLE_ROOT = resolve(__dirname, '..');

let JOB_SEQ = 0;

export async function createDispatcher(opts = {}) {
  const repoRoot   = resolve(opts.repoRoot   ?? join(ORACLE_ROOT, '..', '..'));
  const routerCli  = resolve(opts.routerCli  ?? join(repoRoot, 'core', 'ai-router', 'cli.mjs'));
  const rolesPath  = resolve(opts.rolesPath  ?? join(ORACLE_ROOT, 'roles.json'));
  const agentsDir  = resolve(opts.agentsDir  ?? join(ORACLE_ROOT, 'agents'));
  const jobsLog    = resolve(opts.jobsLog    ?? join(ORACLE_ROOT, 'state', 'jobs.jsonl'));
  const onEvent    = opts.onEvent ?? (() => {});
  // Injectable for tests / dry-run: (argv, {cwd,env}) => Promise<{code,stdout,stderr}>
  const runner     = opts.runner ?? defaultRunner;

  const config = JSON.parse(await readFile(rolesPath, 'utf8'));
  const defaults = config.defaults ?? {};
  const roles = config.roles ?? {};

  const jobs = new Map();          // id -> job record
  let writerChain = Promise.resolve(); // serializes heavy writers

  function emit(type, job) {
    const ev = { type, job: publicView(job) };
    onEvent(ev);
    return ev;
  }

  async function logJob(job) {
    try {
      await mkdir(dirname(jobsLog), { recursive: true });
      await appendFile(jobsLog, JSON.stringify(publicView(job)) + '\n');
    } catch { /* telemetry is never fatal */ }
  }

  function buildInvocation(roleDef, task) {
    const provider = roleDef.provider ?? defaults.provider ?? 'claude';
    const target   = roleDef.target   ?? defaults.target   ?? '.';

    if (roleDef.kind === 'cli') {
      // `ai-router <provider> --target=<repo> -- <expanded cliArgs>`
      const cliArgs = (roleDef.cliArgs ?? ['-p', '{{task}}', '--dangerously-skip-permissions'])
        .map(a => a.replaceAll('{{task}}', task));
      return {
        argv: [routerCli, provider, `--target=${target}`, '--', ...cliArgs],
        promptFile: null,
      };
    }
    if (roleDef.kind === 'agent') {
      // thin agent: JSON in via --prompt-file
      return {
        argv: [routerCli, `--agent=${roleDef.agent}`, `--agents-dir=${agentsDir}`,
               '--consumer=oracle', '--prompt-file=__PROMPT__'],
        promptFile: { input: task, task },
      };
    }
    throw new Error(`role kind not supported: ${roleDef.kind}`);
  }

  async function spawnJob(job, roleDef) {
    job.status = 'running';
    job.startedAt = Date.now();
    emit('started', job);

    const inv = buildInvocation(roleDef, job.task);
    let argv = inv.argv;
    if (inv.promptFile) {
      const pf = join(ORACLE_ROOT, 'state', `prompt-${job.id}.json`);
      await mkdir(dirname(pf), { recursive: true });
      await writeFile(pf, JSON.stringify(inv.promptFile));
      argv = argv.map(a => (a === '--prompt-file=__PROMPT__' ? `--prompt-file=${pf}` : a));
      job.promptFile = pf;
    }
    job.argv = ['node', ...argv];

    try {
      const { code, stdout, stderr } = await runner(['node', ...argv], {
        cwd: repoRoot,
        env: process.env,
        timeoutMs: roleDef.timeoutMs ?? defaults.timeoutMs ?? 600000,
      });
      job.exitCode = code;
      job.result = (stdout ?? '').trim();
      job.stderr = (stderr ?? '').trim();
      job.status = code === 0 ? 'done' : 'failed';
    } catch (err) {
      job.status = 'failed';
      job.error = String(err?.message ?? err);
    }
    job.endedAt = Date.now();
    emit(job.status, job);
    await logJob(job);
    return job;
  }

  // The public entry point the tool-call handler calls.
  // Returns immediately with a job record. For async jobs the caller listens
  // on onEvent for the 'done'/'failed' event (and speaks job.result then).
  function delegate({ role, task, confirmed = false }) {
    const roleDef = roles[role];
    if (!roleDef) {
      return { id: null, status: 'unknown_role', role,
               message: `No such role: ${role}. Known: ${Object.keys(roles).join(', ')}` };
    }
    if (!task || !String(task).trim()) {
      return { id: null, status: 'bad_request', role, message: 'task is required' };
    }

    // Confirm gate for write roles.
    if (roleDef.access === 'write' && !confirmed) {
      return {
        id: null, status: 'needs_confirm', role, task,
        message: `Role "${role}" writes to the environment. Confirm before dispatch.`,
      };
    }

    const job = {
      id: `j${++JOB_SEQ}`,
      role, task,
      kind: roleDef.kind,
      access: roleDef.access,
      weight: roleDef.weight ?? 'light',
      status: 'queued',
      queuedAt: Date.now(),
    };
    jobs.set(job.id, job);
    emit('dispatched', job);

    // Heavy writers run on a serial chain; everything else runs immediately.
    if (job.weight === 'heavy') {
      writerChain = writerChain.then(() => spawnJob(job, roleDef)).catch(() => {});
    } else {
      spawnJob(job, roleDef).catch(() => {});
    }

    return publicView(job); // returns while the job runs in the background
  }

  function getJob(id) { const j = jobs.get(id); return j ? publicView(j) : null; }
  function listJobs() { return [...jobs.values()].map(publicView); }
  function describeRoles() {
    return Object.fromEntries(Object.entries(roles).map(([k, v]) =>
      [k, { access: v.access, weight: v.weight ?? 'light', summary: v.summary }]));
  }

  return { delegate, getJob, listJobs, describeRoles, _config: config };
}

function publicView(job) {
  if (!job) return job;
  const { promptFile, argv, stderr, ...rest } = job;
  return rest;
}

// Real spawn. Streams nothing; collects stdout/stderr; enforces a timeout.
function defaultRunner(argv, { cwd, env, timeoutMs }) {
  return new Promise((res, rej) => {
    const [cmd, ...args] = argv;
    const child = spawn(cmd, args, { cwd, env });
    let stdout = '', stderr = '';
    const timer = timeoutMs ? setTimeout(() => {
      child.kill('SIGKILL');
      rej(new Error(`worker timed out after ${timeoutMs}ms`));
    }, timeoutMs) : null;
    child.stdout.on('data', d => { stdout += d; });
    child.stderr.on('data', d => { stderr += d; });
    child.on('error', err => { if (timer) clearTimeout(timer); rej(err); });
    child.on('close', code => { if (timer) clearTimeout(timer); res({ code, stdout, stderr }); });
  });
}

// ── standalone harness ──────────────────────────────────────────────────────
// Run:  ORACLE_DRY=1 node core/elmaati/server/lib/dispatcher.mjs scout "what is reel 123 status"
// Real: node core/elmaati/server/lib/dispatcher.mjs scout "..."   (actually invokes ai-router)
if (import.meta.main) {
  const [, , role, ...rest] = process.argv;
  const task = rest.join(' ');
  const dry = process.env.ORACLE_DRY === '1';

  const runner = dry
    ? async (argv) => { // echo the command instead of running it
        return { code: 0, stdout: `[DRY] would run:\n  ${argv.join(' ')}`, stderr: '' };
      }
    : undefined;

  const done = new Promise((r) => {
    createDispatcher({
      runner,
      onEvent: (ev) => {
        const j = ev.job ?? {};
        console.log(`• ${ev.type.padEnd(11)} ${j.id ?? ''} ${j.role ?? ''}`.trimEnd());
        if (ev.type === 'done' || ev.type === 'failed') {
          console.log('────────────────────────────────────────');
          console.log(j.result ?? j.error ?? '(no output)');
          r();
        }
      },
    }).then((d) => {
      if (!role || !task) {
        console.log('roles:', JSON.stringify(d.describeRoles(), null, 2));
        console.log('\nusage: [ORACLE_DRY=1] node lib/dispatcher.mjs <role> "<task>"');
        process.exit(0);
      }
      const res = d.delegate({ role, task, confirmed: true });
      if (res.status === 'needs_confirm' || res.status === 'unknown_role' || res.status === 'bad_request') {
        console.log(`✗ ${res.status}: ${res.message}`);
        process.exit(1);
      }
    });
  });
  await done;
}
