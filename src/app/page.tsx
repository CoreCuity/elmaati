'use client';

import React, { useRef } from 'react';
import gsap from 'gsap';
import { useGSAP } from '@gsap/react';
import { Mic, MicOff, Volume2, VolumeX } from 'lucide-react';
import { useLiveAPI } from '../hooks/useLiveAPI';

export default function Elmaati() {
  const vesselRef = useRef<HTMLDivElement>(null);
  const coreRef = useRef<HTMLDivElement>(null);
  const { status, isSpeaking, connect, disconnect } = useLiveAPI();

  useGSAP(() => {
    // Ambient breathing animation
    gsap.to(vesselRef.current, {
      scale: 1.1,
      opacity: 0.6,
      duration: 3,
      repeat: -1,
      yoyo: true,
      ease: 'sine.inOut',
    });

    if (status === 'ready' || status === 'connected') {
      gsap.to(coreRef.current, {
        scale: 1.2,
        backgroundColor: '#ffffff',
        boxShadow: '0 0 60px 20px rgba(197, 179, 88, 0.8)',
        duration: 0.5,
      });
    }

    if (isSpeaking) {
      gsap.to(coreRef.current, {
        scale: 1.4,
        boxShadow: '0 0 80px 30px rgba(197, 179, 88, 1)',
        duration: 0.2,
        repeat: 1,
        yoyo: true,
      });
    }

    if (status === 'idle') {
      gsap.to(coreRef.current, {
        scale: 1,
        backgroundColor: '#ffffff',
        boxShadow: '0 0 40px 10px rgba(197, 179, 88, 0.5)',
        duration: 0.5,
      });
    }
  }, [status, isSpeaking]);

  const toggleConnection = () => {
    if (status === 'idle') {
      connect();
    } else {
      disconnect();
    }
  };

  return (
    <main>
      <div className="elmaati-container">
        <div className="status-text">{status === 'ready' ? 'Online' : status}</div>
        
        <div className="vessel-wrapper" onClick={toggleConnection} style={{ cursor: 'pointer' }}>
          <div ref={vesselRef} className="vessel" />
          <div ref={coreRef} className="vessel-core" />
        </div>

        <div className="controls" style={{ display: 'flex', gap: '20px', opacity: 0.5 }}>
           {status === 'ready' ? <Mic size={20} color="#C5B358" /> : <MicOff size={20} />}
           <Volume2 size={20} color={isSpeaking ? "#C5B358" : "white"} />
        </div>
      </div>

      <div className="transcript-ghost">
        {status === 'idle' ? 'Touch the Vessel to begin.' : isSpeaking ? '' : 'Listening…'}
      </div>

      <footer style={{ position: 'absolute', bottom: '20px', fontSize: '0.6rem', opacity: 0.3, letterSpacing: '0.1em' }}>
        ELMAATI AGI • MULTIMODAL LIVE
      </footer>
    </main>
  );
}
