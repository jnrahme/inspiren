# Event Spec: `bed_exit_risk`

Status: MVP v1
Purpose: define the exact first CV-driven event so implementation does not drift.

## 1. Intent

`bed_exit_risk` is a demo-safe proxy for:

- a resident moving from bed toward standing / exiting
- motion into a dangerous bedside zone
- a caregiver needing immediate visual context

This is **not** a medical fall detector.

## 2. Physical setup assumption

- One room-facing iPhone or iPad mounted in landscape.
- Camera angle captures the bed edge and adjacent floor zone.
- The bed occupies a known region in frame.
- The "danger zone" is configured by calibration, not hard-coded globally.

## 3. Calibration

Before demo use, Sensor Mode must support a simple calibration flow:

1. show the camera preview
2. mark the bed edge
3. mark a polygon or rectangle for the bedside exit zone
4. save that zone locally for the room

MVP rule:

- one zone per room
- no auto-calibration in phase 1

## 4. Detection inputs

Primary signals:

- person detected in frame
- key body landmarks available from Vision body-pose detection
- person centroid or lower-body points entering exit zone
- motion score above resting threshold

Fallback if pose quality is poor:

- bounding-box occupancy in exit zone
- motion spike in exit zone

## 5. Sampling and processing

- process sampled frames, not every frame
- initial target: 4 to 6 analyzed frames per second
- keep stream publishing independent from CV processing loop
- if CPU/thermal pressure rises, CV sampling should degrade before stream stability does

## 6. Event heuristic

Trigger `bed_exit_risk` when all of these are true:

1. a person is detected
2. the person enters or overlaps the configured bedside exit zone
3. motion or pose suggests active transition, not fully static lying posture
4. the condition persists for at least 1.0 second

Suggested initial signal interpretation:

- `personPresent = true` when Vision sees a person with sufficient confidence
- `zoneOccupied = true` when lower-body landmarks or fallback person box intersect exit zone
- `transitioning = true` when motion score is above threshold or pose is upright / rising
- emit event when `personPresent && zoneOccupied && transitioning` holds for 1.0 second

## 7. Event payload

Required fields:

- `roomId`
- `deviceId`
- `eventType = bed_exit_risk`
- `confidence`
- `occurredAt`
- `idempotencyKey`

Metadata fields:

- `zoneId`
- `pose`
- `motionScore`
- `personDetected`
- `transitioning`

## 8. Dedupe and cooldown

- Once emitted, the same event cannot re-fire for 10 seconds unless state clears first.
- Clear state when the person fully leaves the zone for 3 seconds.
- Repeated noisy frames during active cooldown should be ignored.

## 9. Alert mapping

`bed_exit_risk` always creates a `high` priority caregiver alert in MVP v1.

Alert copy:

- title: `Bed Exit Risk`
- body: `Movement detected in bedside exit zone. Open live view now.`

## 10. MVP pass scenarios

### Scenario A: no alert while resting

- person remains in bed area
- no sustained zone occupancy
- no alert should fire

### Scenario B: alert on real exit attempt

- person rises and enters bedside exit zone
- event persists for at least 1 second
- one alert should fire

### Scenario C: no alert spam

- person lingers with noisy partial movement after first alert
- duplicate events should not continuously fire during cooldown

## 11. Known limitations

- single person assumption for phase 1
- no identity tracking
- no fall classification
- no caregiver/resident distinction
- pose quality may degrade under poor lighting or partial occlusion
