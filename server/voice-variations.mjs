// Generate 10 style variations of ONE voice on the native-audio model,
// so you can pick the right delivery character (not just timbre).
//
// Usage:
//   node server/voice-variations.mjs           # defaults to Algenib
//   node server/voice-variations.mjs Charon    # any other voice
//
// Output: voice-samples/<voice>-variations/01-...wav .. 10-...wav
import WebSocket from 'ws';
import fs from 'node:fs';

const KEY = (fs.readFileSync('.env.local', 'utf8').match(/GEMINI_API_KEY=(.+)/) || [])[1].trim().replace(/"/g, '');
const URL = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${KEY}`;
const MODEL = 'models/gemini-2.5-flash-native-audio-latest';
const VOICE = process.argv[2] || 'Algenib';
const OUT = `voice-samples/${VOICE.toLowerCase()}-variations`;

const DARIJA = '"السلام. سميتي لمعطي. شنو بغيتي؟"';

// 10 distinct style directions. Native-audio honors these per-utterance.
const styles = [
  ['01-deep-max',     'in the DEEPEST, LOWEST, MOST RESONANT voice you can — a slow, weighty baritone/bass, like an older Moroccan man speaking from the chest, with maximum gravitas. Take your time, lower your voice as much as possible.'],
  ['02-composed',     'calm, low, and measured — never rushed. Composed gravitas. Each phrase placed deliberately, with weight at the end.'],
  ['03-warm-host',    'warm and welcoming, like a Moroccan host greeting a guest in his home — a small smile in the voice, but still grounded and deep.'],
  ['04-command',      'authoritative and commanding, like an executive making a final statement — clear, deep, decisive, no hesitation.'],
  ['05-intimate',     'soft and intimate, almost whispered, close to the listener — conspiratorial but still deep and resonant.'],
  ['06-mystic',       'slow, ponderous, and mystical — like an oracle revealing a truth from a deep place. Long pauses between phrases.'],
  ['07-elder',        'as an older Moroccan man — paternal, weighty but kind, with the cadence of a grandfather speaking to his family.'],
  ['08-crisp',        'clear, sharp, and decisive — clipped phrasing, deep but precise, no wasted breath. Like a newsreader with weight.'],
  ['09-storyteller',  'like a Moroccan grandfather beginning a story by the fire — slow, weighted, drawing the listener in. A hint of mystery.'],
  ['10-alive',        'warm and alive, with subtle energy — present in the moment, deep but engaged, never flat or robotic.'],
];

function pcmToWav(pcm, rate = 24000) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

function sample(label, styleDirection) {
  return new Promise((res) => {
    const ws = new WebSocket(URL); const chunks = []; let done = false;
    const fin = (note) => {
      if (done) return; done = true; try { ws.close(); } catch {}
      if (chunks.length) {
        const pcm = Buffer.concat(chunks);
        fs.writeFileSync(`${OUT}/${label}.wav`, pcmToWav(pcm));
        console.log(`  ✓ ${label}.wav  (${(pcm.length / 48000).toFixed(1)}s)`);
      } else { console.log(`  ✗ ${label}: ${note || 'no audio'}`); }
      res();
    };
    const prompt = `Say this Moroccan Darija sentence ${styleDirection} Say nothing else: ${DARIJA}`;
    ws.on('open', () => ws.send(JSON.stringify({ setup: { model: MODEL, generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: VOICE } } } } } })));
    ws.on('message', (d) => { let m; try { m = JSON.parse(d.toString()); } catch { return; }
      if (m.setupComplete) ws.send(JSON.stringify({ clientContent: { turns: [{ role: 'user', parts: [{ text: prompt }] }], turnComplete: true } }));
      else if (m.serverContent) { for (const p of (m.serverContent.modelTurn?.parts || [])) if (p.inlineData) chunks.push(Buffer.from(p.inlineData.data, 'base64')); if (m.serverContent.turnComplete) fin(); }
    });
    ws.on('close', (c, r) => fin(r?.toString() || 'closed ' + c));
    ws.on('error', (e) => fin(e.message));
    setTimeout(() => fin('timeout'), 25000);
  });
}

fs.mkdirSync(OUT, { recursive: true });
console.log(`Generating ${styles.length} style variations of "${VOICE}" → ${OUT}/  (model: native-audio)`);
for (const [label, style] of styles) await sample(label, style);
process.exit(0);
