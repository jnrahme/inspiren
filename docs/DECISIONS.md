# MVP Decisions

Date locked: 2026-03-26
Status: Active unless explicitly changed

## Product shape

- We are building a showcase MVP, not a production clinical platform.
- The primary demo is one room, one sensor device, one caregiver device.
- The core product loop is:
  - CV event
  - caregiver alert
  - open live stream
  - acknowledge alert
  - timeline update

## App structure

- We will use one native iOS app for the MVP.
- The app will have two roles:
  - `Sensor Mode`
  - `Caregiver Mode`
- We are not splitting into multiple app targets in phase 1.

## Devices

- `Sensor Mode` must run on a physical iPhone or iPad because camera publishing is required.
- The best demo setup is two physical iOS devices:
  - one for Sensor Mode
  - one for Caregiver Mode
- We should not optimize for simulator-only demos as the primary path.

## Realtime architecture

- Live media path: WebRTC via LiveKit.
- Backend alert fanout path: Server-Sent Events (SSE) from our backend.
- We are not building custom raw WebRTC signaling or SFU infrastructure.
- We are not using HLS as the primary live triage path.

## Backend stack

- Runtime: Node 20
- Language: TypeScript
- Framework: Fastify
- Persistence in phase 1: in-memory store
- Persistence in phase 2: SQLite or Postgres

## iOS stack

- SwiftUI app shell
- AVFoundation for camera/media handling
- Vision for the first CV pipeline
- Core ML only if Vision heuristics are insufficient
- XcodeGen to generate the Xcode project

## Alerts

- First pass uses in-app alerts only.
- We are not implementing APNs in phase 1.
- Alert states for MVP:
  - `new`
  - `acknowledged`
  - `escalated`

## First CV event

- The first real event is `bed_exit_risk`.
- Fallback demo events if implementation risk is too high:
  - `person_detected`
  - `motion_spike`
  - `upright_pose_detected`

## Privacy defaults

- No raw stream recording by default in phase 1.
- No persistent storage of raw video in phase 1.
- Demo data only.
- Privacy overlay support is desirable but not a prerequisite for the first functional loop.

## Acceptance budgets

- stream time-to-first-frame target: under 1.5 seconds on local clean network
- CV event ingest to caregiver alert target: under 500ms local
- caregiver acknowledge roundtrip target: under 300ms local
- repeatable 10-minute demo without app restart
