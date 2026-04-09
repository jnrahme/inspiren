# Demo Validation Plan

Status: MVP v1

## 1. Local topology

Expected local dev setup:

- one backend server
- one local LiveKit server in dev mode
- one physical iOS device in Sensor Mode
- one physical iOS device in Caregiver Mode

Fallback dev setup:

- one physical iOS sensor device
- one caregiver simulator only for partial UI work

## 2. Repeatable demo script

### Demo script A: core happy path

1. Start backend.
2. Start LiveKit locally.
3. Launch Sensor Mode and join `room-a`.
4. Launch Caregiver Mode and join `room-a`.
5. Confirm live stream opens manually.
6. Trigger `bed_exit_risk`.
7. Confirm caregiver sees alert without polling.
8. Open alert detail.
9. Open live view.
10. Acknowledge alert.
11. Confirm timeline updates.

## 3. Manual smoke checklist

- backend health endpoint returns `ok`
- sensor can fetch stream token
- caregiver can fetch stream token
- live stream connects
- caregiver receives at least one realtime alert update
- alert detail opens
- acknowledge changes alert state
- timeline shows both create and acknowledge entries

## 4. Pass/fail budgets

- backend boot to healthy: under 5 seconds local
- live stream time-to-first-frame: under 1.5 seconds local
- CV event ingest to alert created: under 500ms local
- acknowledge action to UI update: under 300ms local
- 10-minute demo run with no crash or forced restart

## 5. Fixtures

We should support two validation modes:

### Mode A: live human movement

- used for real showcase demo

### Mode B: deterministic fixture trigger

- used for repeatable development validation
- should simulate `bed_exit_risk` without needing a human in frame

Recommended first deterministic fixture:

- debug button in Sensor Mode that emits a valid `bed_exit_risk` payload

This is not a substitute for real CV validation. It is a development control.

## 6. Failure drills

We should verify at least these:

- caregiver app joins after sensor already streaming
- sensor temporarily disconnects and reconnects
- duplicate CV event does not create duplicate alerts
- acknowledging an already acknowledged alert does not corrupt state

## 7. Demo artifacts to capture later

- screen recording of caregiver flow
- screenshot set for sensor mode and caregiver mode
- backend log sample for one event lifecycle

## 8. Exit criteria for "showcase ready"

- happy path works end to end three times in a row
- one failure drill is demonstrated successfully
- core metrics are logged or visible during demo
- no manual data editing is required during the run
