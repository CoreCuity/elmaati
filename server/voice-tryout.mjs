// Generate audio samples of Gemini prebuilt voices so you can pick Elmaati's voice by ear.
//
// Usage:
//   node server/voice-tryout.mjs                                     # defaults: half-cascade, voice-samples/
//   node server/voice-tryout.mjs --model=gemini-2.5-flash-native-audio-latest --out=voice-samples/native-audio
//   node server/voice-tryout.mjs Charon Orus                         # specify voices
//
// Output: <out>/<Voice>.wav   (play them, then set voiceName in src/hooks/useLiveAPI.ts)
import WebSocket from 'ws';
import fs from 'node:fs';

const KEY = (fs.readFileSync('.env.local', 'utf8').match(/GEMINI_API_KEY=(.+)/) || [])[1].trim().replace(/"/g, '');
const URL = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${KEY}`;

// ── Parse args: --model=, --out=, rest = voice list ──────────────────────
let MODEL = 'models/gemini-3.1-flash-live-preview';
let OUT = 'voice-samples';
const voices = [];
for (const a of process.argv.slice(2)) {
  if (a.startsWith('--model=')) {
    const v = a.slice('--model='.length);
    MODEL = v.startsWith('models/') ? v : 'models/' + v;
  } else if (a.startsWith('--out=')) {
    OUT = a.slice('--out='.length);
  } else {
    voices.push(a);
  }
}
// Curated for Elmaati: composed, oracle-like, with gravitas.
if (!voices.length) voices.push('Charon', 'Orus', 'Iapetus', 'Algenib', 'Enceladus', 'Umbriel');

// Set env PROMPT_OVERRIDE='...' to use a custom prompt without editing this file.
const LINE = process.env.PROMPT_OVERRIDE || 'Say only this Moroccan Darija sentence in a natural Moroccan accent, nothing else: "السلام. سميتي لمعطي. شنو بغيتي؟"';

function pcmToWav(pcm, rate = 24000) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}

function sample(voice) {
  return new Promise((res) => {
    const ws = new WebSocket(URL); const chunks = []; let done = false;
    const fin = (note) => {
      if (done) return; done = true; try { ws.close(); } catch {}
      if (chunks.length) {
        const pcm = Buffer.concat(chunks);
        fs.writeFileSync(`${OUT}/${voice}.wav`, pcmToWav(pcm));
        console.log(`  ✓ ${voice}.wav  (${(pcm.length / 48000).toFixed(1)}s)`);
      } else { console.log(`  ✗ ${voice}: ${note || 'no audio'}`); }
      res();
    };
    ws.on('open', () => ws.send(JSON.stringify({ setup: { model: MODEL, generationConfig: { responseModalities: ['AUDIO'], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: voice } } } } } })));
    ws.on('message', (d) => { let m; try { m = JSON.parse(d.toString()); } catch { return; }
      if (m.setupComplete) ws.send(JSON.stringify({ clientContent: { turns: [{ role: 'user', parts: [{ text: LINE }] }], turnComplete: true } }));
      else if (m.serverContent) { for (const p of (m.serverContent.modelTurn?.parts || [])) if (p.inlineData) chunks.push(Buffer.from(p.inlineData.data, 'base64')); if (m.serverContent.turnComplete) fin(); }
    });
    ws.on('close', (c, r) => fin(r?.toString() || 'closed ' + c));
    ws.on('error', (e) => fin(e.message));
    setTimeout(() => fin('timeout'), 20000);
  });
}

fs.mkdirSync(OUT, { recursive: true });
console.log(`Generating ${voices.length} samples → ${OUT}/  (model: ${MODEL.replace('models/','')})`);
for (const v of voices) await sample(v);
process.exit(0);
