/**
 * Audio Utilities for Multimodal Live API
 */

export class AudioRecorder {
  private stream: MediaStream | null = null;
  private audioContext: AudioContext | null = null;
  private source: MediaStreamAudioSourceNode | null = null;
  private processor: ScriptProcessorNode | null = null;

  constructor(private sampleRate: number = 16000) {}

  public async start(onAudioData: (base64Data: string) => void) {
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    this.audioContext = new AudioContext({ sampleRate: this.sampleRate });
    this.source = this.audioContext.createMediaStreamSource(this.stream);
    
    // ScriptProcessorNode is deprecated but easier to set up for a minimal UI
    // than an AudioWorklet for now.
    this.processor = this.audioContext.createScriptProcessor(4096, 1, 1);

    this.processor.onaudioprocess = (e) => {
      const inputData = e.inputBuffer.getChannelData(0);
      // Convert to Int16 PCM
      const pcmData = new Int16Array(inputData.length);
      for (let i = 0; i < inputData.length; i++) {
        pcmData[i] = Math.max(-1, Math.min(1, inputData[i])) * 0x7FFF;
      }
      const base64Data = btoa(String.fromCharCode(...new Uint8Array(pcmData.buffer)));
      onAudioData(base64Data);
    };

    this.source.connect(this.processor);
    this.processor.connect(this.audioContext.destination);
  }

  public stop() {
    this.processor?.disconnect();
    this.source?.disconnect();
    this.stream?.getTracks().forEach(track => track.stop());
    this.audioContext?.close();
  }
}

export class AudioPlayer {
  private audioContext: AudioContext | null = null;
  private nextStartTime: number = 0;

  constructor(private sampleRate: number = 24000) {}

  public play(base64Data: string) {
    if (!this.audioContext) {
      this.audioContext = new AudioContext({ sampleRate: this.sampleRate });
      this.nextStartTime = this.audioContext.currentTime;
    }

    const binaryString = atob(base64Data);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i);
    }
    const pcmData = new Int16Array(bytes.buffer);
    const floatData = new Float32Array(pcmData.length);
    for (let i = 0; i < pcmData.length; i++) {
      floatData[i] = pcmData[i] / 0x7FFF;
    }

    const buffer = this.audioContext.createBuffer(1, floatData.length, this.sampleRate);
    buffer.getChannelData(0).set(floatData);

    const source = this.audioContext.createBufferSource();
    source.buffer = buffer;
    source.connect(this.audioContext.destination);

    const startTime = Math.max(this.nextStartTime, this.audioContext.currentTime);
    source.start(startTime);
    this.nextStartTime = startTime + buffer.duration;
  }

  public stop() {
    this.audioContext?.close();
    this.audioContext = null;
    this.nextStartTime = 0;
  }
}
