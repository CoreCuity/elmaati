/**
 * Multimodal Live Client for Gemini 2.0
 */

export type LiveConfig = {
  model: string;
  systemInstruction?: { parts: { text: string }[] };
  generationConfig?: {
    responseModalities?: string[];
    speechConfig?: {
      voiceConfig?: {
        prebuiltVoiceConfig?: {
          voiceName?: string;
        };
      };
    };
  };
  tools?: any[];
};

export class MultimodalLiveClient {
  private ws: WebSocket | null = null;
  private apiKey: string;
  private url: string;
  private config: LiveConfig;

  public onAudioContent: (base64Audio: string) => void = () => {};
  public onContent: (text: string) => void = () => {};
  public onStatusChange: (status: string) => void = () => {};
  public onError: (err: any) => void = () => {};
  public onInterrupted: () => void = () => {};
  public onTurnComplete: () => void = () => {};

  constructor(apiKey: string, config: LiveConfig) {
    this.apiKey = apiKey;
    this.config = config;
    this.url = `ws://localhost:8081`;
  }

  public connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      console.log('Connecting to Elmaati at:', this.url.split('?')[0] + '?key=***');
      this.ws = new WebSocket(this.url);

      this.ws.onopen = () => {
        console.log('Elmaati: WebSocket Open');
        this.onStatusChange('connected');
        this.sendSetup();
        resolve();
      };

      this.ws.onmessage = (event) => {
        this.handleMessage(event.data);
      };

      this.ws.onerror = (event) => {
        console.error('Elmaati: WebSocket Error:', event);
        this.onError(event);
        reject(event);
      };

      this.ws.onclose = (event) => {
        console.log(`Elmaati: WebSocket Closed. Code: ${event.code}, Reason: ${event.reason}`);
        this.onStatusChange('disconnected');
      };
    });
  }

  public disconnect() {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  private sendSetup() {
    // Gemini Live (BidiGenerateContent) JSON uses camelCase field names.
    const setupMessage = {
      setup: {
        model: `models/${this.config.model}`,
        generationConfig: this.config.generationConfig,
        systemInstruction: this.config.systemInstruction,
        tools: this.config.tools,
      },
    };
    this.send(setupMessage);
  }

  public sendAudio(base64Audio: string) {
    // gemini-3.1-flash-live-preview deprecated realtimeInput.mediaChunks;
    // the current field is realtimeInput.audio (a single Blob).
    this.send({
      realtimeInput: {
        audio: {
          mimeType: 'audio/pcm;rate=16000',
          data: base64Audio,
        },
      },
    });
  }

  public sendText(text: string) {
    this.send({
      clientContent: {
        turns: [{
          role: 'user',
          parts: [{ text }],
        }],
        turnComplete: true,
      },
    });
  }

  private send(message: any) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  private handleMessage(data: string) {
    try {
      const msg = JSON.parse(data);

      // Gemini Live responses are camelCase.
      if (msg.setupComplete) {
        this.onStatusChange('ready');
      }

      if (msg.serverContent) {
        const content = msg.serverContent;

        if (content.modelTurn) {
          const parts = content.modelTurn.parts || [];
          for (const part of parts) {
            if (part.inlineData) {
              this.onAudioContent(part.inlineData.data);
            }
            if (part.text) {
              this.onContent(part.text);
            }
          }
        }

        if (content.interrupted) {
          this.onInterrupted();
        }

        if (content.turnComplete) {
          this.onTurnComplete();
        }
      }

      if (msg.toolCall) {
        // Handle tool calls later (n8n / MCP wiring).
      }

      if (msg.error) {
        this.onError(msg.error);
      }
    } catch (e) {
      console.error('Failed to parse message', e);
    }
  }
}
