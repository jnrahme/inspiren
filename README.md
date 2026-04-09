# CareVision

A working prototype of a real-time caregiver alert system with live video streaming and on-device computer vision. Built as a showcase of the kind of mobile infrastructure that powers care-response products in senior living.

**[How it works](https://jnrahme.github.io/inspiren/how-it-works.html)** | **[Why we built it this way](https://jnrahme.github.io/inspiren/technical-decisions.html)** | **[Documentation site](https://jnrahme.github.io/inspiren/)**

## What it does

CareVision demonstrates a complete alert loop from detection to response:

1. A room-facing device captures live video and runs computer vision locally on the device
2. When the system detects something meaningful (like a resident beginning to leave their bed), it sends an event to the backend
3. The backend creates an alert and pushes it to the caregiver in real time, with no polling
4. The caregiver opens a low-latency live stream to see the room immediately
5. The caregiver acknowledges the alert, and the action is recorded in a timeline

The entire flow happens in seconds. The goal is to give caregivers fast, trustworthy visual context so they can make better decisions under time pressure.

## Why it exists

This is a showcase MVP, not a production clinical system. It exists to prove that the hard parts of a care-response product can work together cleanly:

- Real-time video with sub-second latency over WebRTC
- On-device computer vision that respects privacy by never uploading raw video
- A thin backend that orchestrates alerts, tokens, and real-time delivery
- A native iOS app that handles both the sensor role and the caregiver role in one binary

## Architecture

The system has three layers that communicate through well-defined boundaries.

### Backend (Node.js + TypeScript + Fastify)

A lightweight HTTP server that manages the demo lifecycle:

- **Auth**: Issues temporary bearer tokens for sensor and caregiver roles
- **Streaming**: Generates LiveKit JWT tokens so devices can publish and subscribe to WebRTC rooms
- **Event ingest**: Accepts computer vision events from the sensor with idempotency protection (the same event is never processed twice)
- **Alerts**: Maintains a state machine for each alert (new, acknowledged, escalated) with transition rules
- **Real-time delivery**: Uses Server-Sent Events (SSE) to push alerts and timeline updates to connected caregivers without polling
- **Timeline**: Records an audit trail of every event and action
- **Laptop sensor**: Serves a browser-based sensor page so you can demo the system using your Mac's webcam instead of a second iPhone

Data lives in memory for this prototype. It resets when the server restarts, which is fine for a demo but would need durable storage in production.

### iOS App (SwiftUI + AVFoundation + Vision + LiveKit)

A single native app with two modes, selected at launch:

**Sensor Mode** turns the device into a room monitor:
- Opens the camera using AVFoundation
- Runs Apple Vision requests on every frame to detect people and estimate body pose
- Feeds pose data into a bed-exit detection state machine that classifies activity (in bed, sitting up, standing, exiting)
- Publishes the camera feed over WebRTC via LiveKit
- Sends structured events to the backend when something clinically relevant happens
- Includes calibration sliders so you can define the bedside exit zone for the room

**Caregiver Mode** turns the device into an alert dashboard:
- Connects to the backend's SSE stream to receive alerts in real time
- Shows an alert inbox with priority badges
- Opens the live video stream from the sensor with a single tap
- Renders a motion overlay on the video (skeleton, person bounding box, motion trail) so the caregiver can see what the vision system is detecting
- Supports acknowledging and escalating alerts, with changes reflected in the timeline

### Communication

| Path | Protocol | Purpose |
|------|----------|---------|
| Live video | WebRTC via LiveKit | Low-latency media streaming between sensor and caregiver |
| Alerts and updates | Server-Sent Events | Real-time push from backend to caregiver (no polling) |
| Actions and queries | REST | Session creation, token requests, alert acknowledgment, timeline |
| Motion overlay | LiveKit data channel | Best-effort delivery of skeleton and detection data |

## The computer vision pipeline

Detection runs entirely on-device using Apple's Vision framework. No video frames leave the phone.

The pipeline runs at roughly 5 frames per second and processes each frame through two Vision requests:

1. **Human rectangle detection** determines whether a person is in the frame and where
2. **Body pose estimation** maps 19 anatomical landmarks (shoulders, hips, knees, ankles, etc.)

From the pose data, the system calculates:

- **Upright score**: How vertical the person's torso is, based on shoulder-hip alignment
- **Leg extension score**: Whether legs are extended (lying down) or bent (sitting/standing)
- **Motion score**: How much the person's position has changed since the last frame
- **Zone occupancy**: Whether the person's center of mass is inside the calibrated bedside exit zone

These signals feed into a state machine (`BedExitDetector`) that classifies the current activity and decides when to fire an event. The state machine uses persistence windows (a condition must hold for 0.6 to 0.8 seconds before triggering) and cooldown windows (8 to 10 seconds between repeated events) to avoid noisy false positives.

## Running it locally

### Prerequisites

- Node.js 20+
- Xcode 15+ with iOS 17 SDK
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A local [LiveKit server](https://docs.livekit.io/home/self-hosting/local/) for WebRTC (optional for basic testing)

### Start the backend

```bash
cd backend
npm install
npm run build
npm start
```

The server starts at `http://127.0.0.1:8787`. You should see a log line confirming it is listening.

### Verify with the smoke test

```bash
cd backend
npm run smoke
```

This exercises the full happy path: session creation, token generation, event ingest, alert creation, SSE delivery, and acknowledgment.

### Try the laptop sensor

Open `http://127.0.0.1:8787/demo/laptop-sensor` in your browser. This page uses your Mac's webcam as a stand-in for the room sensor device. It publishes video to a LiveKit room and provides buttons to manually trigger CV events and alerts.

### Build the iOS app

```bash
cd ios
xcodegen generate
open CareVisionSample.xcodeproj
```

Build and run on a simulator for **Caregiver Mode** (the camera is not available in the simulator, so Sensor Mode requires a physical device).

### Two-device demo (recommended)

The best way to see the full loop:

1. Start the backend on your Mac
2. Open the laptop sensor page in your browser (this is your "room device")
3. Run the iOS app on a physical iPhone in **Caregiver Mode**
4. In the app's settings, change the base URL to your Mac's LAN IP (e.g., `http://192.168.1.118:8787`)
5. Trigger an event from the laptop sensor page
6. Watch the alert arrive on the phone, open the live stream, and acknowledge it

### Physical iPhone sensor (advanced)

If you have two iPhones:

1. iPhone A in **Sensor Mode** (back camera facing the room)
2. iPhone B in **Caregiver Mode** (receives alerts, views live stream)

Both devices need to reach the backend over your local network.

## Project structure

```
.
├── backend/
│   ├── src/
│   │   ├── index.ts          # Fastify server, all API routes
│   │   ├── types.ts          # Shared type definitions
│   │   ├── store.ts          # In-memory data store and pub/sub
│   │   ├── config.ts         # Environment configuration
│   │   └── livekit.ts        # LiveKit token generation
│   ├── scripts/
│   │   └── smoke.mjs         # Integration smoke test
│   ├── public/
│   │   └── laptop-sensor.html # Browser-based sensor for demos
│   ├── package.json
│   └── tsconfig.json
├── ios/
│   ├── CareVisionSample/
│   │   ├── App/              # App entry point and root navigation
│   │   ├── Core/             # Theme and shared data models
│   │   ├── Features/
│   │   │   ├── Sensor/       # Sensor mode views and view model
│   │   │   ├── Caregiver/    # Caregiver mode views and view model
│   │   │   ├── Common/       # Shared UI components
│   │   │   └── RolePicker/   # Mode selection
│   │   └── Services/         # API client, SSE, LiveKit, camera, detection
│   ├── project.yml           # XcodeGen configuration
│   └── README.md
└── docs/
    ├── DECISIONS.md           # Architecture and scope decisions
    ├── api-contract.md        # Complete REST API specification
    ├── event-spec-bed-exit-risk.md  # CV event detection spec
    └── demo-validation.md     # Demo script and performance budgets
```

## Performance targets

These are the budgets for the local demo environment:

| Metric | Target |
|--------|--------|
| Time to first video frame | < 1.5 seconds |
| CV event to alert delivery | < 500 ms |
| Alert acknowledgment to UI update | < 300 ms |
| Vision pipeline throughput | 4-6 frames/second |
| Demo stability | 10 minutes without crash |

## Tech stack

| Layer | Technology |
|-------|-----------|
| Backend | Node.js, TypeScript, Fastify, Zod |
| Real-time media | WebRTC via LiveKit |
| Real-time events | Server-Sent Events (SSE) |
| iOS UI | SwiftUI |
| iOS camera | AVFoundation |
| iOS computer vision | Apple Vision framework |
| iOS streaming | LiveKit iOS SDK |
| Project generation | XcodeGen |

## What is not included

This is a demonstration, not a production system. It intentionally omits:

- Persistent database storage (state lives in memory)
- Push notifications via APNs
- Real user authentication (tokens are demo-scoped)
- Clinical-grade detection accuracy
- Multi-room management
- Video recording or replay
- HIPAA compliance infrastructure

These are all solvable problems, but they are out of scope for a showcase that focuses on proving the real-time architecture works.

## License

MIT
