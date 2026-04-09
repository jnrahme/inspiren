# iOS Workstream

Goal: build the native app that demonstrates both room capture and caregiver
response.

## Recommended role model

For the showcase MVP, use one native iOS app with two modes:

- `Sensor Mode`
- `Caregiver Mode`

This keeps the first build simple and easier to demo.

Important:

- real Sensor Mode testing requires a physical iOS device
- best demo setup uses two physical iOS devices

## Recommended stack

- SwiftUI for app UI
- AVFoundation for capture and media handling
- Vision for built-in computer vision tasks
- Core ML if a custom model becomes necessary
- a WebRTC-capable iOS client SDK for live room streaming
- SSE client support for backend-driven alert updates

## Suggested module split

- `AppShell`
- `Feature/RolePicker`
- `Feature/Sensor`
- `Feature/Caregiver`
- `Feature/Alerts`
- `Feature/Timeline`
- `Service/Streaming`
- `Service/Vision`
- `Service/API`
- `Service/Realtime`
- `Core/Models`
- `Core/Design`

## Phase 1 deliverables

- app boots into role picker
- caregiver inbox renders fake alerts
- backend connection works

## Phase 2 deliverables

- Sensor Mode publishes camera stream
- Caregiver Mode subscribes to live stream
- stream state UI exists

## Phase 3 deliverables

- Vision pipeline emits first real event
- alert detail screen opens from event
- acknowledge action works

## Technical spikes to do early

- stream startup performance
- Vision frame-sampling strategy
- battery / thermal impact in Sensor Mode
- app behavior on background / foreground transitions

## First implementation checklist

- create Xcode project
- add app architecture skeleton
- add environment config
- add mock alert data
- add backend client
- add streaming client wrapper
- add Vision service wrapper

## Current implementation

Files:

- `project.yml`
- `CareVisionSample/App/*`
- `CareVisionSample/Core/*`
- `CareVisionSample/Services/*`
- `CareVisionSample/Features/*`

What works now:

- generated Xcode project via `xcodegen`
- SwiftUI role picker and demo setup sheet
- `Sensor Mode` shell with:
  - AVFoundation preview
  - Vision human detection requests
  - exit-zone overlay
  - zone calibration sliders
  - backend CV event submission
- `Sensor Mode` LiveKit publisher with:
  - room connect flow
  - local video render surface
  - start / stop live stream controls
- `Caregiver Mode` shell with:
  - alert inbox
  - timeline view
  - SSE-backed realtime updates
  - alert acknowledgement action
  - LiveKit room subscription
  - live remote room video surface

Build:

```bash
cd ios
xcodegen generate
xcodebuild -project CareVisionSample.xcodeproj -scheme CareVisionSample -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Open in Xcode:

```bash
cd ios
open CareVisionSample.xcodeproj
```

Important runtime notes:

- the simulator builds cleanly, but `Sensor Mode` camera preview is best on a
  physical iPhone
- if the backend runs on your Mac, change the app base URL to your Mac's LAN IP
  before testing on device
- the fastest two-screen demo now uses the Mac laptop sensor page at
  `http://127.0.0.1:8787/demo/laptop-sensor` plus a physical iPhone in
  `Caregiver Mode`
- `Sensor Mode` live publishing now uses the same capture pipeline as the local
  Vision loop, so preview + CV + stream can stay active together on device
- the simulator can still join caregiver rooms cleanly, but real sensor-camera
  validation is best on physical hardware
