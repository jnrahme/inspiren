export interface AppConfig {
  port: number;
  livekitUrl: string;
  livekitApiKey: string;
  livekitApiSecret: string;
  corsOrigin: string;
}

export function loadConfig(): AppConfig {
  return {
    port: Number(process.env.PORT ?? 8787),
    livekitUrl: process.env.LIVEKIT_URL ?? 'ws://127.0.0.1:7880',
    livekitApiKey: process.env.LIVEKIT_API_KEY ?? 'devkey',
    livekitApiSecret: process.env.LIVEKIT_API_SECRET ?? 'secret',
    corsOrigin: process.env.CORS_ORIGIN ?? '*',
  };
}
