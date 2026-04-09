import CoreMedia
import Foundation
import LiveKit

private final class BufferPublisherState: @unchecked Sendable {
  private let lock = NSLock()
  private var capturer: BufferCapturer?
  private var hasBufferedFrame = false

  func setCapturer(_ capturer: BufferCapturer?) {
    lock.lock()
    self.capturer = capturer
    hasBufferedFrame = false
    lock.unlock()
  }

  func markDisconnected() {
    setCapturer(nil)
  }

  func capture(_ sampleBuffer: CMSampleBuffer) {
    lock.lock()
    let capturer = capturer
    if capturer != nil {
      hasBufferedFrame = true
    }
    lock.unlock()

    capturer?.capture(sampleBuffer)
  }

  func hasFrame() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return hasBufferedFrame
  }
}

@MainActor
final class LiveKitRoomManager: NSObject, ObservableObject {
  @Published private(set) var connectionSummary = "Stream idle"
  @Published private(set) var localVideoTrack: VideoTrack?
  @Published private(set) var remoteVideoTrack: VideoTrack?
  @Published private(set) var overlay: MotionOverlayFrame = .empty
  @Published private(set) var errorMessage: String?
  @Published private(set) var isConnected = false
  @Published private(set) var isPublishing = false

  private let settings: DemoSettings
  private let role: DemoRole
  private let displayName: String
  private let participantName: String
  private let bufferPublisherState = BufferPublisherState()

  private var room: Room?
  private var bufferVideoTrack: LocalVideoTrack?
  private var pendingOverlayPayload: MotionOverlayPayload?
  private var overlayPublishTask: Task<Void, Never>?

  private enum PublishStrategy {
    case none
    case camera
    case bufferTrack
  }

  init(
    settings: DemoSettings,
    role: DemoRole,
    displayName: String,
    participantName: String
  ) {
    self.settings = settings
    self.role = role
    self.displayName = displayName
    self.participantName = participantName
    super.init()
  }

  func connectSubscriber() async {
    await connect(publishStrategy: .none)
  }

  func connectCameraPublisher() async {
    await connect(publishStrategy: .camera)
  }

  func connectBufferPublisher() async {
    await connect(publishStrategy: .bufferTrack)
  }

  func publishOverlay(roomId: String, deviceId: String, overlay: MotionOverlayFrame) {
    pendingOverlayPayload = MotionOverlayPayload(
      roomId: roomId,
      deviceId: deviceId,
      overlay: overlay
    )

    guard overlayPublishTask == nil else { return }

    overlayPublishTask = Task { [weak self] in
      await self?.flushOverlayQueue()
    }
  }

  nonisolated func capture(sampleBuffer: CMSampleBuffer) {
    bufferPublisherState.capture(sampleBuffer)
  }

  private func connect(publishStrategy: PublishStrategy) async {
    if isConnected {
      if publishStrategy == .camera && !isPublishing {
        await enableCameraPublishing()
      } else if publishStrategy == .bufferTrack && !isPublishing {
        await enableBufferPublishing()
      }
      return
    }

    connectionSummary = "Preparing LiveKit token"
    errorMessage = nil

    do {
      let client = try APIClient(baseURLString: settings.baseURLString)
      let session = try await client.createDemoSession(displayName: displayName, role: role)
      let stream = try await client.fetchStreamToken(
        accessToken: session.accessToken,
        roomId: settings.roomId,
        participantName: participantName,
        role: role
      )

      let room = Room(delegate: self)
      try await room.connect(url: stream.livekitUrl, token: stream.token)

      self.room = room
      isConnected = true
      connectionSummary = "Connected to \(stream.roomId)"
      syncExistingTracks()

      if publishStrategy == .camera {
        await enableCameraPublishing()
      } else if publishStrategy == .bufferTrack {
        await enableBufferPublishing()
      }
    } catch {
      errorMessage = error.localizedDescription
      connectionSummary = "Stream connection failed"
    }
  }

  func disconnect() async {
    defer {
      overlayPublishTask?.cancel()
      overlayPublishTask = nil
      pendingOverlayPayload = nil
      room = nil
      localVideoTrack = nil
      remoteVideoTrack = nil
      overlay = .empty
      isConnected = false
      isPublishing = false
      connectionSummary = "Stream idle"
      bufferVideoTrack = nil
      bufferPublisherState.markDisconnected()
    }

    guard let room else { return }

    if isPublishing {
      do {
        try await room.localParticipant.setCamera(enabled: false)
      } catch {
        errorMessage = error.localizedDescription
      }
    }

    await room.disconnect()
  }

  private func enableCameraPublishing() async {
    guard let room else { return }

    #if targetEnvironment(simulator)
      connectionSummary = "Connected. Camera publish needs a physical iPhone."
      errorMessage = "LiveKit camera publishing is not supported in the iOS Simulator."
      isPublishing = false
      return
    #else
      do {
        connectionSummary = "Publishing live camera"
        try await room.localParticipant.setCamera(enabled: true)
        isPublishing = true
        errorMessage = nil
      } catch {
        isPublishing = false
        errorMessage = error.localizedDescription
        connectionSummary = "Camera publish failed"
      }
    #endif
  }

  private func enableBufferPublishing() async {
    guard let room else { return }

    if bufferVideoTrack == nil {
      let track = LocalVideoTrack.createBufferTrack(
        name: "sensor-\(settings.roomId)",
        source: .camera
      )
      bufferVideoTrack = track
      localVideoTrack = track
      bufferPublisherState.setCapturer(track.capturer as? BufferCapturer)
    }

    guard let track = bufferVideoTrack else {
      connectionSummary = "Buffer publisher unavailable"
      errorMessage = "The buffer-backed video track could not be created."
      return
    }

    connectionSummary = "Waiting for first camera frame"

    for _ in 0 ..< 20 where !bufferPublisherState.hasFrame() {
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    guard bufferPublisherState.hasFrame() else {
      connectionSummary = "Camera frames not ready"
      errorMessage = "Sensor Mode needs live camera frames before the room can publish."
      return
    }

    do {
      connectionSummary = "Publishing live camera"
      _ = try await room.localParticipant.publish(videoTrack: track)
      isPublishing = true
      errorMessage = nil
    } catch {
      isPublishing = false
      errorMessage = error.localizedDescription
      connectionSummary = "Camera publish failed"
    }
  }

  private func syncExistingTracks() {
    guard let room else { return }

    for publication in room.localParticipant.trackPublications.values {
      if let track = publication.track as? VideoTrack {
        localVideoTrack = track
        break
      }
    }

    for participant in room.remoteParticipants.values {
      for publication in participant.trackPublications.values {
        if let track = publication.track as? VideoTrack {
          remoteVideoTrack = track
          return
        }
      }
    }
  }

  private func flushOverlayQueue() async {
    defer {
      overlayPublishTask = nil
    }

    while let payload = pendingOverlayPayload {
      pendingOverlayPayload = nil

      guard let room, isConnected else {
        continue
      }

      do {
        let data = try JSONEncoder().encode(payload)
        let options = DataPublishOptions(topic: DemoRealtimeTopic.motionOverlay, reliable: false)
        try await room.localParticipant.publish(data: data, options: options)
      } catch {
        // Overlay transport is best-effort and should not break the live room.
      }
    }
  }
}

extension LiveKitRoomManager: RoomDelegate {
  nonisolated func room(
    _ room: Room,
    participant: LocalParticipant,
    didPublishTrack publication: LocalTrackPublication
  ) {
    guard let track = publication.track as? VideoTrack else { return }

    Task { @MainActor in
      self.localVideoTrack = track
      self.isPublishing = true
      self.connectionSummary = "Publishing live camera"
    }
  }

  nonisolated func room(
    _ room: Room,
    participant: RemoteParticipant,
    didSubscribeTrack publication: RemoteTrackPublication
  ) {
    guard let track = publication.track as? VideoTrack else { return }

    Task { @MainActor in
      self.remoteVideoTrack = track
      self.connectionSummary = "Receiving live stream"
    }
  }

  nonisolated func room(
    _ room: Room,
    participant: RemoteParticipant,
    didUnsubscribeTrack publication: RemoteTrackPublication
  ) {
    guard publication.track is VideoTrack else { return }

    Task { @MainActor in
      self.remoteVideoTrack = nil
      self.overlay = .empty
      self.connectionSummary = "Connected. Waiting for live video."
    }
  }

  nonisolated func room(
    _ room: Room,
    participant: RemoteParticipant?,
    didReceiveData data: Data,
    forTopic topic: String,
    encryptionType _: EncryptionType
  ) {
    guard topic == DemoRealtimeTopic.motionOverlay else { return }
    guard let payload = try? JSONDecoder().decode(MotionOverlayPayload.self, from: data) else { return }

    Task { @MainActor in
      guard payload.roomId == self.settings.roomId else { return }
      self.overlay = payload.overlay
    }
  }

  nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
    Task { @MainActor in
      self.isConnected = false
      self.isPublishing = false
      self.localVideoTrack = nil
      self.remoteVideoTrack = nil
      self.overlay = .empty
      if let error {
        self.errorMessage = error.localizedDescription
        self.connectionSummary = "LiveKit disconnected"
      } else {
        self.connectionSummary = "Stream idle"
      }
    }
  }
}
