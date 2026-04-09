const baseUrl = process.env.BACKEND_BASE_URL ?? 'http://127.0.0.1:8787';

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

async function requestJson(path, { token, method = 'GET', body } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    method,
    headers: {
      Accept: 'application/json',
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;

  if (!response.ok) {
    throw new Error(
      `Request failed ${method} ${path}: ${response.status} ${response.statusText} ${text}`,
    );
  }

  return payload;
}

function createSseClient(path, token) {
  const controller = new AbortController();
  const queue = [];
  const waiters = [];
  let closed = false;
  let closeReason = null;
  let resolveReady;
  let rejectReady;
  let didResolveReady = false;

  const ready = new Promise((resolve, reject) => {
    resolveReady = resolve;
    rejectReady = reject;
  });

  const settleNextWaiter = () => {
    if (!waiters.length || !queue.length) return;

    for (let index = 0; index < waiters.length; index += 1) {
      const waiter = waiters[index];
      const queueIndex = queue.findIndex((event) => event.event === waiter.eventName);
      if (queueIndex === -1) continue;

      const [event] = queue.splice(queueIndex, 1);
      waiters.splice(index, 1);
      clearTimeout(waiter.timeoutId);
      waiter.resolve(event);
      return settleNextWaiter();
    }
  };

  const rejectAll = (error) => {
    closeReason = error;
    while (waiters.length) {
      const waiter = waiters.shift();
      clearTimeout(waiter.timeoutId);
      waiter.reject(error);
    }
  };

  const parseFrame = (frame) => {
    let eventName = 'message';
    const dataLines = [];

    for (const line of frame.split(/\r?\n/)) {
      if (!line || line.startsWith(':')) continue;
      if (line.startsWith('event:')) {
        eventName = line.slice('event:'.length).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        dataLines.push(line.slice('data:'.length).trimStart());
      }
    }

    if (!dataLines.length) return;

    queue.push({
      event: eventName,
      data: JSON.parse(dataLines.join('\n')),
    });
    settleNextWaiter();
  };

  const readerLoop = (async () => {
    const response = await fetch(`${baseUrl}${path}`, {
      headers: {
        Accept: 'text/event-stream',
        Authorization: `Bearer ${token}`,
      },
      signal: controller.signal,
    });

    if (!response.ok || !response.body) {
      throw new Error(
        `SSE connection failed ${path}: ${response.status} ${response.statusText}`,
      );
    }

    didResolveReady = true;
    resolveReady();

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (!closed) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });

      while (buffer.includes('\n\n')) {
        const boundary = buffer.indexOf('\n\n');
        const frame = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 2);
        parseFrame(frame);
      }
    }
  })()
    .catch((error) => {
      if (!didResolveReady) {
        rejectReady(error);
      }
      if (!closed) {
        rejectAll(error);
      }
    })
    .finally(() => {
      closed = true;
      if (closeReason) {
        rejectAll(closeReason);
      }
    });

  return {
    ready,
    async waitFor(eventName, timeoutMs = 5000) {
      const queued = queue.findIndex((event) => event.event === eventName);
      if (queued !== -1) {
        const [event] = queue.splice(queued, 1);
        return event;
      }

      if (closed && closeReason) {
        throw closeReason;
      }

      return new Promise((resolve, reject) => {
        const timeoutId = setTimeout(() => {
          const index = waiters.findIndex((waiter) => waiter.timeoutId === timeoutId);
          if (index !== -1) {
            waiters.splice(index, 1);
          }
          reject(new Error(`Timed out waiting for SSE event ${eventName}`));
        }, timeoutMs);

        waiters.push({ eventName, timeoutId, resolve, reject });
        settleNextWaiter();
      });
    },
    async close() {
      closed = true;
      controller.abort();
      await readerLoop.catch(() => undefined);
    },
  };
}

async function main() {
  const roomId = `room-${Date.now()}`;
  const sensorDeviceId = 'sensor-device-01';
  const occurredAt = new Date().toISOString();

  console.log(`Smoke test against ${baseUrl}`);

  const health = await requestJson('/health');
  assert(health.status === 'ok', 'Health endpoint did not report ok');

  const sensorSession = await requestJson('/auth/demo-session', {
    method: 'POST',
    body: {
      displayName: 'Sensor Device',
      role: 'sensor',
    },
  });
  const caregiverSession = await requestJson('/auth/demo-session', {
    method: 'POST',
    body: {
      displayName: 'Caregiver Demo',
      role: 'caregiver',
    },
  });

  assert(sensorSession.accessToken, 'Sensor access token missing');
  assert(caregiverSession.accessToken, 'Caregiver access token missing');

  const sensorStream = await requestJson('/stream/token', {
    token: sensorSession.accessToken,
    method: 'POST',
    body: {
      roomId,
      participantName: 'sensor-device',
      role: 'sensor',
    },
  });
  const caregiverStream = await requestJson('/stream/token', {
    token: caregiverSession.accessToken,
    method: 'POST',
    body: {
      roomId,
      participantName: 'caregiver-device',
      role: 'caregiver',
    },
  });

  assert(sensorStream.token, 'Sensor stream token missing');
  assert(caregiverStream.token, 'Caregiver stream token missing');

  const sse = createSseClient('/events/stream', caregiverSession.accessToken);
  await sse.ready;
  const readyEvent = await sse.waitFor('connection.ready');
  assert(readyEvent.data?.id, 'SSE connection.ready payload missing id');

  const overlayResponse = await requestJson('/overlay/frames', {
    token: sensorSession.accessToken,
    method: 'POST',
    body: {
      roomId,
      deviceId: sensorDeviceId,
      overlay: {
        updatedAt: occurredAt,
        personDetected: true,
        poseLabel: 'motion-tracked',
        motionScore: 0.62,
        personBox: {
          x: 0.22,
          y: 0.14,
          width: 0.28,
          height: 0.42,
        },
        trail: [
          { x: 0.24, y: 0.34 },
          { x: 0.31, y: 0.38 },
          { x: 0.39, y: 0.43 },
        ],
        skeleton: [],
      },
    },
  });
  assert(overlayResponse.accepted === true, 'Overlay frame was not accepted');

  const overlayUpdated = await sse.waitFor('overlay.updated');
  assert(overlayUpdated.data?.roomId === roomId, 'Overlay room id did not match request');
  assert(
    overlayUpdated.data?.overlay?.trail?.length === 3,
    'Overlay payload did not include expected trail points',
  );

  const cvResponse = await requestJson('/events/cv', {
    token: sensorSession.accessToken,
    method: 'POST',
    body: {
      idempotencyKey: `bed-exit-${Date.now()}`,
      roomId,
      deviceId: sensorDeviceId,
      eventType: 'bed_exit_risk',
      confidence: 0.94,
      occurredAt,
      metadata: {
        roi: 'left-exit-zone',
        posture: 'upright',
      },
    },
  });

  assert(cvResponse.accepted === true, 'CV event was not accepted');
  assert(cvResponse.alert?.id, 'CV event did not create an alert');

  const alertCreated = await sse.waitFor('alert.created');
  assert(alertCreated.data?.id === cvResponse.alert.id, 'SSE alert id did not match ingest response');

  const alerts = await requestJson(`/alerts?roomId=${encodeURIComponent(roomId)}`, {
    token: caregiverSession.accessToken,
  });
  assert(alerts.alerts.length === 1, 'Expected exactly one alert in alert list');

  const acknowledged = await requestJson(`/alerts/${cvResponse.alert.id}/acknowledge`, {
    token: caregiverSession.accessToken,
    method: 'POST',
    body: {
      actorName: 'Caregiver Demo',
    },
  });
  assert(
    acknowledged.alert.state === 'acknowledged',
    'Alert acknowledgement did not update state',
  );

  const alertUpdated = await sse.waitFor('alert.updated');
  assert(
    alertUpdated.data?.state === 'acknowledged',
    'SSE alert.updated did not deliver acknowledged state',
  );

  const timeline = await requestJson(`/timeline?roomId=${encodeURIComponent(roomId)}`, {
    token: caregiverSession.accessToken,
  });
  assert(
    Array.isArray(timeline.entries) && timeline.entries.length >= 2,
    'Expected timeline to contain created and acknowledged entries',
  );

  await sse.close();
  console.log('Smoke test passed');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
