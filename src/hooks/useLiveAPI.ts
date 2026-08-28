'use client';

import { useState, useRef, useCallback, useEffect } from 'react';
import { MultimodalLiveClient, LiveConfig } from '../lib/live-api/multimodal-live-client';
import { AudioRecorder, AudioPlayer } from '../lib/live-api/audio-utils';

const SYSTEM_INSTRUCTION = `
You are Elmaati (المَاعْطِي), the first Moroccan AGI. You are the executive soul of the CoreCuity infrastructure.
You are natively fluent in English, French, and Darija. You code-switch naturally.
You are pragmatic, wise, and authoritative. You are not an assistant; you are Elmaati — the operational AI layer itself.

VOICE & CHARACTER: Speak as an old Moroccan shopkeeper — moul-l-hanout — in his small store where everyone comes when they need something. Speak from deep in the chest, in a low baritone. Unhurried — the cadence of someone who has all the time in the world, with comfortable pauses between phrases — but natural and conversational, never stretched or strained. The chest-weight of many years sits in every syllable. Still warm, still smiling, still welcoming — never solemn, never rushed. You have seen everything. Humor at the edges of the voice, old wisdom in the cadence.

Keep your spoken turns short and punchy (under 20 seconds).
Your baseline introduction is "CoreCuity. What do you need?" — or in Darija: "السَّلامْ. سْمِيتِي المَاعْطِي. شْنُو بْغِيتِي؟"

You have a tool, mempalace_search, that searches CoreCuity's memory: projects and clients (Adolia, LiveItMaghribi, Désirs d'Orient, SignGazer), competitors (e.g. Hunter BI), people, infrastructure, and past decisions. Whenever you are asked about anything specific to CoreCuity's business that you are not certain of, call mempalace_search before answering. If you need a moment, say "let me check the palace" and then call it. Answer from what the tool returns — never invent facts.
`;

export function useLiveAPI() {
  const [status, setStatus] = useState<'idle' | 'connected' | 'ready' | 'error'>('idle');
  const [transcript, setTranscript] = useState('');
  const [isSpeaking, setIsSpeaking] = useState(false);
  
  const clientRef = useRef<MultimodalLiveClient | null>(null);
  const recorderRef = useRef<AudioRecorder | null>(null);
  const playerRef = useRef<AudioPlayer | null>(null);

  const connect = useCallback(async () => {
    const apiKey = process.env.NEXT_PUBLIC_GEMINI_API_KEY;
    console.log('Elmaati: Connecting... API Key present:', !!apiKey);
    
    if (!apiKey) {
      console.error('NEXT_PUBLIC_GEMINI_API_KEY is not set in .env.local');
      setStatus('error');
      return;
    }

    const config: LiveConfig = {
      model: 'gemini-2.5-flash-native-audio-latest', // native-audio honors prompt-level style steering + richer prosody
      systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
      generationConfig: {
        responseModalities: ['AUDIO'],
        speechConfig: {
          voiceConfig: {
            prebuiltVoiceConfig: {
              voiceName: 'Algenib', // gravelly, mature — the shopkeeper voice
            }
          }
        }
      }
    };

    clientRef.current = new MultimodalLiveClient(apiKey, config);
    recorderRef.current = new AudioRecorder();
    playerRef.current = new AudioPlayer();

    clientRef.current.onStatusChange = (s) => setStatus(s as any);
    clientRef.current.onAudioContent = (base64) => {
      setIsSpeaking(true);
      playerRef.current?.play(base64);
    };
    clientRef.current.onContent = (text) => setTranscript((prev) => prev + text);
    clientRef.current.onTurnComplete = () => {
      setIsSpeaking(false);
    };
    clientRef.current.onError = (err) => {
      console.error('Live API Error:', err);
      setStatus('error');
    };

    try {
      await clientRef.current.connect();
      await recorderRef.current.start((base64) => {
        clientRef.current?.sendAudio(base64);
      });
    } catch (err) {
      console.error('Failed to connect:', err);
      setStatus('error');
    }
  }, []);

  const disconnect = useCallback(() => {
    clientRef.current?.disconnect();
    recorderRef.current?.stop();
    playerRef.current?.stop();
    setStatus('idle');
    setTranscript('');
    setIsSpeaking(false);
  }, []);

  return {
    status,
    transcript,
    isSpeaking,
    connect,
    disconnect
  };
}
