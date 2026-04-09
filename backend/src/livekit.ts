import { AccessToken } from 'livekit-server-sdk';

import type { AppConfig } from './config.js';
import type { DemoRole } from './types.js';

interface StreamTokenInput {
  roomId: string;
  participantName: string;
  role: DemoRole;
}

export async function createStreamToken(
  config: AppConfig,
  input: StreamTokenInput,
) {
  const accessToken = new AccessToken(
    config.livekitApiKey,
    config.livekitApiSecret,
    {
      identity: input.participantName,
      ttl: '2h',
      name: input.participantName,
    },
  );

  accessToken.addGrant({
    roomJoin: true,
    room: input.roomId,
    canPublish: input.role === 'sensor',
    canSubscribe: input.role === 'caregiver',
  });

  return {
    roomId: input.roomId,
    participantName: input.participantName,
    livekitUrl: config.livekitUrl,
    token: await accessToken.toJwt(),
    permissions: {
      canPublish: input.role === 'sensor',
      canSubscribe: input.role === 'caregiver',
    },
  };
}
