# API Contract

Status: MVP v1
Backend stack target: Node + Fastify + SSE + LiveKit token issuing

## 1. Auth model

For MVP, the backend issues a simple demo session bearer token.

Header for protected API calls:

```http
Authorization: Bearer <demo-session-token>
```

Protected endpoints:

- `POST /stream/token`
- `POST /events/cv`
- `GET /alerts`
- `GET /timeline`
- `GET /events/stream`
- `POST /alerts/:id/acknowledge`
- `POST /alerts/:id/escalate`

## 2. `GET /health`

Response:

```json
{
  "status": "ok",
  "service": "care-vision-backend",
  "time": "2026-03-26T23:30:00.000Z"
}
```

## 3. `POST /auth/demo-session`

Purpose:

- create a temporary session for the app

Request:

```json
{
  "displayName": "Joey Demo",
  "role": "caregiver"
}
```

Response:

```json
{
  "session": {
    "id": "sess_123",
    "displayName": "Joey Demo",
    "role": "caregiver"
  },
  "accessToken": "demo_abc123"
}
```

## 4. `POST /stream/token`

Purpose:

- mint a LiveKit token for publish or subscribe access

Request:

```json
{
  "roomId": "room-a",
  "participantName": "sensor-01",
  "role": "sensor"
}
```

Response:

```json
{
  "roomId": "room-a",
  "participantName": "sensor-01",
  "livekitUrl": "ws://127.0.0.1:7880",
  "token": "<livekit-jwt>",
  "permissions": {
    "canPublish": true,
    "canSubscribe": false
  }
}
```

Notes:

- `role = sensor` publishes
- `role = caregiver` subscribes

## 5. `POST /events/cv`

Purpose:

- ingest a CV event emitted by Sensor Mode

Request:

```json
{
  "idempotencyKey": "evt_room-a_20260326T233000Z_bedexit_01",
  "roomId": "room-a",
  "deviceId": "sensor-01",
  "eventType": "bed_exit_risk",
  "confidence": 0.86,
  "occurredAt": "2026-03-26T23:30:00.000Z",
  "metadata": {
    "zoneId": "bedside-left",
    "pose": "upright",
    "motionScore": 0.73
  }
}
```

Response:

```json
{
  "accepted": true,
  "eventId": "cve_123",
  "alert": {
    "id": "alert_123",
    "state": "new",
    "priority": "high"
  }
}
```

Idempotency rule:

- if the same `idempotencyKey` is received again, backend returns the original accepted response without creating a second alert

## 6. `GET /alerts`

Purpose:

- fetch current alert list for caregiver UI

Query params:

- `state` optional
- `roomId` optional

Response:

```json
{
  "alerts": [
    {
      "id": "alert_123",
      "roomId": "room-a",
      "deviceId": "sensor-01",
      "eventType": "bed_exit_risk",
      "title": "Bed Exit Risk",
      "body": "Movement detected in bedside exit zone. Open live view now.",
      "priority": "high",
      "state": "new",
      "createdAt": "2026-03-26T23:30:00.000Z"
    }
  ]
}
```

## 7. `POST /alerts/:id/acknowledge`

Request:

```json
{
  "actorName": "Joey Demo"
}
```

Response:

```json
{
  "alert": {
    "id": "alert_123",
    "state": "acknowledged",
    "updatedAt": "2026-03-26T23:30:04.000Z"
  }
}
```

## 8. `POST /alerts/:id/escalate`

Request:

```json
{
  "actorName": "Joey Demo",
  "reason": "Needs immediate assistance"
}
```

Response:

```json
{
  "alert": {
    "id": "alert_123",
    "state": "escalated",
    "updatedAt": "2026-03-26T23:30:06.000Z"
  }
}
```

## 9. `GET /timeline`

Query params:

- `roomId` optional

Response:

```json
{
  "entries": [
    {
      "id": "tl_123",
      "kind": "alert_created",
      "roomId": "room-a",
      "alertId": "alert_123",
      "createdAt": "2026-03-26T23:30:00.000Z",
      "summary": "Bed Exit Risk detected"
    },
    {
      "id": "tl_124",
      "kind": "alert_acknowledged",
      "roomId": "room-a",
      "alertId": "alert_123",
      "createdAt": "2026-03-26T23:30:04.000Z",
      "summary": "Alert acknowledged by Joey Demo"
    }
  ]
}
```

## 10. `GET /events/stream`

Purpose:

- SSE stream for caregiver realtime UI

Event types:

- `alert.created`
- `alert.updated`
- `timeline.created`

Example SSE frame:

```text
event: alert.created
data: {"id":"alert_123","roomId":"room-a","state":"new","priority":"high"}
```

## 11. Alert state machine

Allowed transitions:

- `new -> acknowledged`
- `new -> escalated`
- `acknowledged -> escalated`

Disallowed in MVP v1:

- reopen
- resolve
- dismiss

## 12. Room naming convention

- default room id for first demo: `room-a`
- device id format: `sensor-01`
- caregiver participant example: `caregiver-joey`
