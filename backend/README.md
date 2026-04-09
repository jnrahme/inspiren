# Backend Workstream

Goal: provide the realtime and event backbone for the MVP without overbuilding.

## Responsibilities

- issue session / room tokens
- receive CV events from the room device
- create caregiver alerts
- provide realtime updates to caregiver clients
- persist alert and timeline state
- expose simple status endpoints

## Recommended backend shape

Keep the backend thin.

Suggested components:

- API server
- token service
- event ingest service
- alert rules service
- realtime fanout layer
- persistence layer

## Suggested data objects

- `room`
- `device`
- `stream_session`
- `cv_event`
- `alert`
- `alert_action`
- `timeline_entry`

## Suggested MVP endpoints

- `GET /health`
- `POST /auth/demo-session`
- `POST /stream/token`
- `POST /events/cv`
- `GET /events/stream`
- `GET /alerts`
- `POST /alerts/:id/acknowledge`
- `POST /alerts/:id/escalate`
- `GET /timeline`

## Realtime requirements

- caregiver should receive new alerts without polling
- alert status changes should propagate quickly
- stream metadata should be available to the client

## Persistence recommendation

Start simple:

- SQLite for the first local demo or
- Postgres if we want a more realistic multi-session dev setup

The key is to avoid spending week one on database ceremony.

## Observability for the MVP

Track:

- event ingest time
- alert creation latency
- stream token issuance latency
- client connection failures
- room/device heartbeat status

## First implementation checklist

- create service skeleton
- add config and secrets strategy
- add token endpoint
- add fake event ingest
- add fake alert generation
- add caregiver realtime updates
- add ack/escalate actions

## Current implementation

Files:

- `package.json`
- `src/index.ts`
- `src/store.ts`
- `src/livekit.ts`
- `src/config.ts`
- `src/types.ts`
- `scripts/smoke.mjs`

What works now:

- demo session auth
- LiveKit JWT issuance for sensor and caregiver roles
- host-aware LiveKit URL rewriting so LAN phones do not receive loopback stream
  URLs when the backend is called over the network
- CV event ingest with idempotency handling
- alert creation and timeline entry generation
- SSE event stream for caregiver updates
- alert acknowledgement and escalation state changes
- laptop sensor page at `/demo/laptop-sensor` with:
  - Mac webcam publish into the room
  - manual CV event trigger button
  - phone setup instructions for the iOS caregiver app

Run locally:

```bash
cd backend
npm install
npm run build
npm start
```

Verification:

```bash
cd backend
npm run smoke
```

Laptop demo:

```bash
open http://127.0.0.1:8787/demo/laptop-sensor
```

Current backend limitations:

- in-memory store only
- no real database migrations or durability
- no auth beyond demo bearer tokens
- no room lifecycle management beyond token minting
