import AVFoundation
import Foundation

@MainActor
final class SensorModeViewModel: ObservableObject {
  @Published private(set) var cameraState: CameraRuntimeState = .idle
  @Published private(set) var detection: DetectionSnapshot = .idle
  @Published private(set) var overlay: MotionOverlayFrame = .empty
  @Published private(set) var streamSummary = "No publisher token requested yet."
  @Published private(set) var eventSummary = "No CV event has been submitted yet."
  @Published private(set) var errorMessage: String?
  @Published var zone: ZoneConfiguration

  let cameraManager = SensorCameraManager()
  let streamManager: LiveKitRoomManager

  private let settings: DemoSettings
  private var apiClient: APIClient?
  private var accessToken: String?
  private var hasStarted = false
  private var isUploadingOverlay = false
  private var pendingOverlayPayload: MotionOverlayPayload?
  private let iso8601Formatter = ISO8601DateFormatter()

  var cameraSession: AVCaptureSession {
    cameraManager.session
  }

  init(settings: DemoSettings) {
    self.settings = settings
    zone = settings.zone
    streamManager = LiveKitRoomManager(
      settings: settings,
      role: .sensor,
      displayName: settings.sensorDisplayName,
      participantName: settings.sensorDeviceId
    )
    let streamManager = streamManager

    cameraManager.updateZone(settings.zone)
    cameraManager.onStateChange = { [weak self] state in
      self?.cameraState = state
    }
    cameraManager.onSnapshot = { [weak self] snapshot in
      self?.detection = snapshot
    }
    cameraManager.onOverlayFrame = { [weak self] overlay in
      guard let self else { return }
      self.overlay = overlay
      self.streamManager.publishOverlay(
        roomId: self.settings.roomId,
        deviceId: self.settings.sensorDeviceId,
        overlay: overlay
      )
      self.queueOverlayRelay(overlay)
    }
    cameraManager.onSampleBuffer = { [weak streamManager] sampleBuffer in
      streamManager?.capture(sampleBuffer: sampleBuffer)
    }
    cameraManager.onActivityTrigger = { [weak self] trigger in
      guard let self else { return }
      Task {
        await self.submit(trigger: trigger, source: "vision")
      }
    }
  }

  func startIfNeeded() async {
    guard !hasStarted else { return }
    hasStarted = true
    await connect()
  }

  func reconnect() async {
    cameraManager.stop()
    await streamManager.disconnect()
    hasStarted = true
    await connect()
  }

  func stop() {
    cameraManager.stop()
    overlay = MotionOverlayFrame.cleared(updatedAt: iso8601Formatter.string(from: Date()))
    queueOverlayRelay(overlay)
    Task {
      await streamManager.disconnect()
    }
    hasStarted = false
  }

  func updateZone(_ updatedZone: ZoneConfiguration) {
    zone = updatedZone.clamped
    cameraManager.updateZone(zone)
  }

  func triggerManualEvent() async {
    let trigger = BedExitTrigger(
      eventType: .bedExitRisk,
      confidence: max(detection.confidence, 0.91),
      occurredAt: Date(),
      poseLabel: detection.poseLabel == .none ? .transitional : detection.poseLabel,
      activityLabel: detection.activityLabel == .clear ? .standingNearBed : detection.activityLabel,
      motionScore: max(detection.motionScore, 0.62)
    )
    await submit(trigger: trigger, source: "manual")
  }

  func startStreaming() async {
    await streamManager.connectBufferPublisher()
  }

  func stopStreaming() async {
    await streamManager.disconnect()
  }

  private func connect() async {
    do {
      let client = try APIClient(baseURLString: settings.baseURLString)
      _ = try await client.health()
      let session = try await client.createDemoSession(
        displayName: settings.sensorDisplayName,
        role: .sensor
      )
      let stream = try await client.fetchStreamToken(
        accessToken: session.accessToken,
        roomId: settings.roomId,
        participantName: settings.sensorDeviceId,
        role: .sensor
      )

      apiClient = client
      accessToken = session.accessToken
      overlay = .empty
      streamSummary = "Publisher token ready for \(stream.roomId) at \(stream.livekitUrl)"
      errorMessage = nil
      cameraManager.updateZone(zone)
      cameraManager.start()
    } catch {
      errorMessage = error.localizedDescription
      cameraState = .failed(error.localizedDescription)
      streamSummary = "Publisher token unavailable."
    }
  }

  private func submit(trigger: BedExitTrigger, source: String) async {
    guard let apiClient, let accessToken else {
      eventSummary = "Backend session is not ready."
      return
    }

    let timestamp = iso8601Formatter.string(from: trigger.occurredAt)
    let payload = CVEventRequest(
      idempotencyKey: "\(source)-\(trigger.eventType.rawValue)-\(settings.roomId)-\(Int(trigger.occurredAt.timeIntervalSince1970 * 1000))",
      roomId: settings.roomId,
      deviceId: settings.sensorDeviceId,
      eventType: trigger.eventType,
      confidence: trigger.confidence,
      occurredAt: timestamp,
      metadata: [
        "zoneId": "bedside-exit-zone",
        "pose": trigger.poseLabel.rawValue,
        "activity": trigger.activityLabel.rawValue,
        "motionScore": String(format: "%.2f", trigger.motionScore),
        "uprightScore": String(format: "%.2f", detection.uprightScore),
        "legExtensionScore": String(format: "%.2f", detection.legExtensionScore),
        "personDetected": detection.personDetected ? "true" : "false",
        "transitioning": detection.transitioning ? "true" : "false",
        "source": source,
      ]
    )

    do {
      let response = try await apiClient.sendCVEvent(accessToken: accessToken, payload: payload)
      if let alert = response.alert {
        let verb = response.accepted ? "submitted" : "deduped"
        eventSummary = "\(trigger.eventType.rawValue) \(verb). Alert \(alert.id) is \(alert.state.rawValue)."
      } else {
        eventSummary = "CV event sent without alert payload."
      }
      errorMessage = nil
    } catch {
      eventSummary = "CV event failed to submit."
      errorMessage = error.localizedDescription
    }
  }

  private func queueOverlayRelay(_ overlay: MotionOverlayFrame) {
    pendingOverlayPayload = MotionOverlayPayload(
      roomId: settings.roomId,
      deviceId: settings.sensorDeviceId,
      overlay: overlay
    )

    guard !isUploadingOverlay else {
      return
    }

    isUploadingOverlay = true
    Task { [weak self] in
      await self?.flushOverlayRelayQueue()
    }
  }

  private func flushOverlayRelayQueue() async {
    while let payload = pendingOverlayPayload {
      pendingOverlayPayload = nil

      guard let apiClient, let accessToken else {
        continue
      }

      do {
        _ = try await apiClient.sendMotionOverlay(accessToken: accessToken, payload: payload)
      } catch {
        // Overlay relay remains best-effort in the demo path.
      }
    }

    isUploadingOverlay = false
  }
}
