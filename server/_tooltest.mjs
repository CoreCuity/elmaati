import dotenv from 'dotenv';
import { WebSocket } from 'ws';
dotenv.config({ path: '.env.local' }); dotenv.config();
const KEY = process.env.GEMINI_API_KEY;
const URL = `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${KEY}`;

const mempalace = { name:'mempalace_search', description:'search', parameters:{ type:'OBJECT', properties:{ query:{ type:'STRING', description:'q' } }, required:['query'] } };
const delegateEnum = { name:'delegate', description:'d', parameters:{ type:'OBJECT', properties:{ role:{ type:'STRING', enum:['scout','operator','desktop'], description:'r' }, task:{ type:'STRING', description:'t' } }, required:['role','task'] } };
const delegateNoEnum = { name:'delegate', description:'d', parameters:{ type:'OBJECT', properties:{ role:{ type:'STRING', description:'r' }, task:{ type:'STRING', description:'t' } }, required:['role','task'] } };
const confirmBool = { name:'confirm', description:'c', parameters:{ type:'OBJECT', properties:{ token:{ type:'STRING', description:'tok' }, approved:{ type:'BOOLEAN', description:'a' } }, required:['token','approved'] } };

function tryTools(label, fns) {
  return new Promise((res) => {
    const ws = new WebSocket(URL);
    let done = false;
    const finish = (r) => { if (done) return; done = true; try{ws.close();}catch{} res(`${label.padEnd(22)} ${r}`); };
    ws.on('open', () => ws.send(JSON.stringify({ setup: {
      model: 'models/gemini-2.5-flash-native-audio-latest',
      generationConfig: { responseModalities:['AUDIO'], speechConfig:{ voiceConfig:{ prebuiltVoiceConfig:{ voiceName:'Algenib' } } } },
      systemInstruction: { parts:[{ text:'test' }] },
      tools: [{ functionDeclarations: fns }],
    } })));
    ws.on('message', async (d) => {
      let t = typeof d === 'string' ? d : (d.toString ? d.toString() : new TextDecoder().decode(d));
      if (t.includes('setupComplete')) finish('✅ setupComplete (OK)');
    });
    ws.on('close', (c, r) => finish(`✗ closed code=${c} ${r?.toString()||''}`));
    ws.on('error', (e) => finish(`✗ error ${e?.message}`));
    setTimeout(() => finish('… timeout'), 8000);
  });
}

console.log(await tryTools('1 mempalace only', [mempalace]));
console.log(await tryTools('2 +delegate(enum)', [mempalace, delegateEnum]));
console.log(await tryTools('3 +delegate(no enum)', [mempalace, delegateNoEnum]));
console.log(await tryTools('4 +confirm(BOOLEAN)', [mempalace, delegateNoEnum, confirmBool]));
process.exit(0);
