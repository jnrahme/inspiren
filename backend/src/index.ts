import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { networkInterfaces, type NetworkInterfaceInfo } from 'node:os';

import cors from '@fastify/cors';
import Fastify, { type FastifyRequest } from 'fastify';
import { ZodError, z } from 'zod';

import { loadConfig } from './config.js';
import { createStreamToken } from './livekit.js';
import { InMemoryStore } from './store.js';

const config = loadConfig();
const app = Fastify({ logger: true });
const store = new InMemoryStore();
const laptopSensorTemplate = await readFile(
  new URL('../public/laptop-sensor.html', import.meta.url),
  'utf8',
);
const livekitClientBundle = await readFile(
  new URL('../node_modules/livekit-client/dist/livekit-client.esm.mjs', import.meta.url),
  'utf8',
);
const lanAddresses = getLanAddresses();

class HttpError extends Error {
  constructor(
    readonly statusCode: number,
    message: string,
  ) {
    super(message);
  }
}

const demoSessionSchema = z.object({
  displayName: z.string().min(1).max(100),
  role: z.enum(['sensor', 'caregiver']),
});

const streamTokenSchema = z.object({
  roomId: z.string().min(1),
  participantName: z.string().min(1),
  role: z.enum(['sensor', 'caregiver']),
});

const cvEventSchema = z.object({
  idempotencyKey: z.string().min(1),
  roomId: z.string().min(1),
  deviceId: z.string().min(1),
  eventType: z.enum([
    'bed_exit_risk',
    'person_detected',
    'motion_spike',
    'no_motion',
    'upright_pose_detected',
  ]),
  confidence: z.number().min(0).max(1),
  occurredAt: z.string().datetime(),
  metadata: z.record(z.string(), z.unknown()).default({}),
});

const overlayPointSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
});

const overlayRectSchema = z.object({
  x: z.number().min(0).max(1),
  y: z.number().min(0).max(1),
  width: z.number().min(0).max(1),
  height: z.number().min(0).max(1),
});

const overlaySegmentSchema = z.object({
  from: overlayPointSchema,
  to: overlayPointSchema,
  confidence: z.number().min(0).max(1),
});

const motionOverlaySchema = z.object({
  roomId: z.string().min(1),
  deviceId: z.string().min(1),
  overlay: z.object({
    updatedAt: z.string().datetime(),
    personDetected: z.boolean(),
    poseLabel: z.string().min(1),
    motionScore: z.number().min(0).max(1),
    personBox: overlayRectSchema.nullable().optional().default(null),
    trail: z.array(overlayPointSchema).max(24),
    skeleton: z.array(overlaySegmentSchema).max(32),
  }),
});

const alertActionSchema = z.object({
  actorName: z.string().min(1).max(100),
  reason: z.string().max(200).optional(),
});

function normalizeHeaderValue(value: string | string[] | undefined) {
  if (Array.isArray(value)) {
    return value[0]?.split(',')[0]?.trim();
  }
  return value?.split(',')[0]?.trim();
}

function isLoopbackHost(hostname: string | undefined) {
  if (!hostname) return false;
  const normalized = hostname.replace(/^\[|\]$/g, '').toLowerCase();
  return (
    normalized === '127.0.0.1' ||
    normalized === 'localhost' ||
    normalized === '::1'
  );
}

function lanAddressRank(address: string) {
  if (address.startsWith('192.168.')) return 0;
  if (address.startsWith('10.')) return 1;
  if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(address)) return 2;
  return 3;
}

function getLanAddresses() {
  const addresses = new Set<string>();
  const interfaces: NetworkInterfaceInfo[] = [];

  for (const entries of Object.values(networkInterfaces())) {
    if (!entries) {
      continue;
    }
    interfaces.push(...entries);
  }

  for (const entry of interfaces) {
    if (entry.internal || entry.family !== 'IPv4') {
      continue;
    }

    addresses.add(entry.address);
  }

  return [...addresses].sort((left, right) => {
    const rankDifference = lanAddressRank(left) - lanAddressRank(right);
    if (rankDifference !== 0) {
      return rankDifference;
    }
    return left.localeCompare(right, undefined, { numeric: true });
  });
}

function stringifyUrl(url: URL) {
  return url.toString().replace(/\/$/, '');
}

function getCurrentOrigin(request: FastifyRequest) {
  const forwardedHost = normalizeHeaderValue(request.headers['x-forwarded-host']);
  const host = forwardedHost ?? request.headers.host ?? `${request.hostname}:${config.port}`;
  return `${request.protocol}://${host}`;
}

function resolveLiveKitUrl(request: FastifyRequest) {
  try {
    const url = new URL(config.livekitUrl);
    if (!isLoopbackHost(url.hostname)) {
      return stringifyUrl(url);
    }

    if (!isLoopbackHost(request.hostname)) {
      url.hostname = request.hostname;
      return stringifyUrl(url);
    }

    return stringifyUrl(url);
  } catch {
    return config.livekitUrl;
  }
}

function buildLaptopSensorBootstrap(request: FastifyRequest) {
  const currentOrigin = getCurrentOrigin(request);
  const suggestedPhoneBaseUrl =
    lanAddresses[0] && isLoopbackHost(request.hostname)
      ? `${request.protocol}://${lanAddresses[0]}:${config.port}`
      : currentOrigin;

  return {
    currentOrigin,
    defaultRoomId: 'room-demo-a',
    defaultDeviceId: 'laptop-sensor-01',
    lanAddresses,
    suggestedPhoneBaseUrl,
    suggestedLocalPageUrl: `http://127.0.0.1:${config.port}/demo/laptop-sensor`,
  };
}

function serializeInlineJson(value: unknown) {
  return JSON.stringify(value).replace(/</g, '\\u003c');
}

function getBearerToken(authHeader: string | undefined) {
  if (!authHeader?.startsWith('Bearer ')) return undefined;
  return authHeader.slice('Bearer '.length).trim();
}

async function requireSession(request: { headers: { authorization?: string } }) {
  const token = getBearerToken(request.headers.authorization);
  const session = store.getSessionByToken(token);
  if (!session) {
    throw new HttpError(401, 'Missing or invalid bearer token');
  }
  return session;
}

await app.register(cors, {
  origin: config.corsOrigin === '*' ? true : config.corsOrigin,
});

app.setErrorHandler((error, _request, reply) => {
  if (error instanceof ZodError) {
    return reply.code(400).send({
      error: 'Bad Request',
      message: 'Request validation failed',
      issues: error.issues,
    });
  }

  if (error instanceof HttpError) {
    return reply.code(error.statusCode).send({
      error: 'Request Error',
      message: error.message,
    });
  }

  app.log.error(error);
  return reply.code(500).send({
    error: 'Internal Server Error',
    message: 'Unexpected backend failure',
  });
});

app.get('/health', async () => ({
  status: 'ok',
  service: 'care-vision-backend',
  time: new Date().toISOString(),
}));

app.get('/demo/laptop-sensor', async (request, reply) => {
  const bootstrap = buildLaptopSensorBootstrap(request);
  const page = laptopSensorTemplate.replace(
    '__CARE_VISION_BOOTSTRAP__',
    serializeInlineJson(bootstrap),
  );

  return reply
    .type('text/html; charset=utf-8')
    .header('Cache-Control', 'no-store')
    .send(page);
});

app.get('/demo/vendor/livekit-client.esm.mjs', async (_request, reply) => {
  return reply
    .type('text/javascript; charset=utf-8')
    .header('Cache-Control', 'public, max-age=86400')
    .send(livekitClientBundle);
});

app.post('/auth/demo-session', async (request) => {
  const body = demoSessionSchema.parse(request.body);
  const session = store.createSession(body);
  return {
    session: {
      id: session.id,
      displayName: session.displayName,
      role: session.role,
    },
    accessToken: session.token,
  };
});

app.post('/stream/token', async (request) => {
  await requireSession(request);
  const body = streamTokenSchema.parse(request.body);
  return createStreamToken(
    {
      ...config,
      livekitUrl: resolveLiveKitUrl(request),
    },
    body,
  );
});

app.post('/events/cv', async (request) => {
  await requireSession(request);
  const body = cvEventSchema.parse(request.body);
  const result = store.createOrGetCVEvent(body);

  return {
    accepted: result.accepted,
    eventId: result.event.id,
    alert: result.alert
      ? {
          id: result.alert.id,
          state: result.alert.state,
          priority: result.alert.priority,
        }
      : null,
  };
});

app.post('/overlay/frames', async (request) => {
  await requireSession(request);
  const body = motionOverlaySchema.parse(request.body);
  store.updateMotionOverlay(body);
  return { accepted: true };
});

app.get('/alerts', async (request) => {
  await requireSession(request);
  const query = z
    .object({
      roomId: z.string().optional(),
      state: z.enum(['new', 'acknowledged', 'escalated']).optional(),
    })
    .parse(request.query);

  return {
    alerts: store.listAlerts(query.roomId, query.state),
  };
});

app.get('/timeline', async (request) => {
  await requireSession(request);
  const query = z
    .object({
      roomId: z.string().optional(),
    })
    .parse(request.query);

  return {
    entries: store.listTimeline(query.roomId),
  };
});

app.post('/alerts/:id/acknowledge', async (request) => {
  await requireSession(request);
  const params = z.object({ id: z.string().min(1) }).parse(request.params);
  const body = alertActionSchema.parse(request.body);
  const alert = store.updateAlert({
    id: params.id,
    nextState: 'acknowledged',
    actorName: body.actorName,
  });

  if (!alert) {
    throw new HttpError(404, 'Alert not found');
  }

  return {
    alert: {
      id: alert.id,
      state: alert.state,
      updatedAt: alert.updatedAt,
    },
  };
});

app.post('/alerts/:id/escalate', async (request) => {
  await requireSession(request);
  const params = z.object({ id: z.string().min(1) }).parse(request.params);
  const body = alertActionSchema.parse(request.body);
  const alert = store.updateAlert({
    id: params.id,
    nextState: 'escalated',
    actorName: body.actorName,
    reason: body.reason,
  });

  if (!alert) {
    throw new HttpError(404, 'Alert not found');
  }

  return {
    alert: {
      id: alert.id,
      state: alert.state,
      updatedAt: alert.updatedAt,
    },
  };
});

app.get('/events/stream', async (request, reply) => {
  await requireSession(request);

  reply.hijack();
  reply.raw.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
  });

  const send = (eventName: string, payload: unknown) => {
    reply.raw.write(`event: ${eventName}\n`);
    reply.raw.write(`data: ${JSON.stringify(payload)}\n\n`);
  };

  const subscriberId = store.addSubscriber((event) => {
    send(event.event, event.data);
  });

  send('connection.ready', {
    id: randomUUID(),
    time: new Date().toISOString(),
  });

  const heartbeat = setInterval(() => {
    reply.raw.write(': keep-alive\n\n');
  }, 15000);

  request.raw.on('close', () => {
    clearInterval(heartbeat);
    store.removeSubscriber(subscriberId);
  });

  return;
});

const address = await app.listen({
  port: config.port,
  host: '0.0.0.0',
});

app.log.info(`care-vision-backend listening on ${address}`);
