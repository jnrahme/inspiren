@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Vision

final class SensorCameraManager: NSObject, @unchecked Sendable {
  let session = AVCaptureSession()

  var onStateChange: ((CameraRuntimeState) -> Void)?
  var onSnapshot: ((DetectionSnapshot) -> Void)?
  var onOverlayFrame: ((MotionOverlayFrame) -> Void)?
  var onActivityTrigger: ((BedExitTrigger) -> Void)?
  var onSampleBuffer: ((CMSampleBuffer) -> Void)?

  private let captureQueue = DispatchQueue(label: "carevision.capture.queue")
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sequenceHandler = VNSequenceRequestHandler()
  private let detector = BedExitDetector()
  private let iso8601Formatter = ISO8601DateFormatter()

  private var lastAnalysisAt: Date = .distantPast
  private var lastObservationBox: CGRect?
  private var lastObservationAt: Date?
  private var motionTrail: [CGPoint] = []
  private var isConfigured = false
  private var zone = ZoneConfiguration.defaultBedside

  private let skeletonConnections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
    (.nose, .neck),
    (.neck, .root),
    (.leftShoulder, .rightShoulder),
    (.leftShoulder, .leftElbow),
    (.leftElbow, .leftWrist),
    (.rightShoulder, .rightElbow),
    (.rightElbow, .rightWrist),
    (.leftShoulder, .leftHip),
    (.rightShoulder, .rightHip),
    (.leftHip, .rightHip),
    (.leftHip, .leftKnee),
    (.leftKnee, .leftAnkle),
    (.rightHip, .rightKnee),
    (.rightKnee, .rightAnkle),
  ]

  private struct PoseSignals {
    let poseLabel: PersonPoseLabel
    let uprightScore: Double
    let legExtensionScore: Double
    let aspectRatio: Double
  }

  func updateZone(_ zone: ZoneConfiguration) {
    self.zone = zone.clamped
    detector.reset()
  }

  func start() {
    Task {
      await startInternal()
    }
  }

  func stop() {
    captureQueue.async {
      if self.session.isRunning {
        self.session.stopRunning()
      }
      self.detector.reset()
      self.lastObservationBox = nil
      self.lastObservationAt = nil
      self.motionTrail.removeAll()
      DispatchQueue.main.async {
        self.onStateChange?(.idle)
      }
    }
  }

  private func startInternal() async {
    DispatchQueue.main.async {
      self.onStateChange?(.starting)
    }

    let granted = await requestVideoAccessIfNeeded()
    guard granted else {
      DispatchQueue.main.async {
        self.onStateChange?(.failed("Camera permission was denied. Sensor Mode can still use manual trigger."))
      }
      return
    }

    do {
      let configured = try await configureIfNeeded()
      guard configured else {
        return
      }

      captureQueue.async {
        if !self.session.isRunning {
          self.session.startRunning()
        }
        DispatchQueue.main.async {
          self.onStateChange?(.live)
        }
      }
    } catch {
      DispatchQueue.main.async {
        self.onStateChange?(.failed(error.localizedDescription))
      }
    }
  }

  private func requestVideoAccessIfNeeded() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .video) { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }

  private func configureIfNeeded() async throws -> Bool {
    if isConfigured {
      return true
    }

    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
      DispatchQueue.main.async {
        self.onStateChange?(.fallback("No back camera is available. Use a physical iPhone or manual event trigger."))
      }
      return false
    }

    return try await withCheckedThrowingContinuation { continuation in
      captureQueue.async {
        do {
          self.session.beginConfiguration()
          self.session.sessionPreset = .high

          self.session.inputs.forEach { self.session.removeInput($0) }
          self.session.outputs.forEach { self.session.removeOutput($0) }

          let input = try AVCaptureDeviceInput(device: camera)
          guard self.session.canAddInput(input) else {
            throw NSError(domain: "SensorCameraManager", code: 1, userInfo: [
              NSLocalizedDescriptionKey: "Unable to add camera input to the capture session.",
            ])
          }
          self.session.addInput(input)

          self.videoOutput.alwaysDiscardsLateVideoFrames = true
          self.videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
          ]
          self.videoOutput.setSampleBufferDelegate(self, queue: self.captureQueue)

          guard self.session.canAddOutput(self.videoOutput) else {
            throw NSError(domain: "SensorCameraManager", code: 2, userInfo: [
              NSLocalizedDescriptionKey: "Unable to add video output to the capture session.",
            ])
          }
          self.session.addOutput(self.videoOutput)

          self.session.commitConfiguration()
          self.isConfigured = true
          continuation.resume(returning: true)
        } catch {
          self.session.commitConfiguration()
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    let now = Date()
    guard now.timeIntervalSince(lastAnalysisAt) >= 0.2 else {
      return
    }
    lastAnalysisAt = now

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }

    let humanRequest = VNDetectHumanRectanglesRequest()
    humanRequest.upperBodyOnly = false

    let poseRequest = VNDetectHumanBodyPoseRequest()

    do {
      try sequenceHandler.perform([humanRequest, poseRequest], on: pixelBuffer, orientation: .up)
    } catch {
      DispatchQueue.main.async {
        self.onStateChange?(.failed("Vision request failed: \(error.localizedDescription)"))
      }
      return
    }

    let humanObservation = humanRequest.results?.first
    let poseObservation = poseRequest.results?.first
    let uiBox = humanObservation.map { visionRectToUICoordinates($0.boundingBox) }
    let poseSignals = postureSignals(from: poseObservation, box: uiBox)
    let poseDetected = poseSignals.poseLabel != .none && poseSignals.poseLabel != .occupancyOnly
    let zoneOccupied = uiBox.map { $0.intersects(zone.rect) } ?? false
    let motionScore = motionScore(for: uiBox, now: now)
    let personDetected = humanObservation != nil || poseDetected
    let confidence = Double(humanObservation?.confidence ?? (poseDetected ? 0.74 : 0))
    let transitioning = zoneOccupied && (
      motionScore > 0.16 ||
      poseSignals.poseLabel == .sittingUp ||
      poseSignals.poseLabel == .standing ||
      poseSignals.poseLabel == .transitional
    )
    let skeleton = skeletonSegments(from: poseObservation)
    let trail = motionTrailPoints(for: uiBox, personDetected: personDetected)

    var snapshot = DetectionSnapshot(
      personDetected: personDetected,
      zoneOccupied: zoneOccupied,
      transitioning: transitioning,
      confidence: confidence,
      poseLabel: poseSignals.poseLabel,
      activityLabel: .clear,
      motionScore: motionScore,
      uprightScore: poseSignals.uprightScore,
      legExtensionScore: poseSignals.legExtensionScore,
      aspectRatio: poseSignals.aspectRatio,
      lastUpdated: now
    )
    let overlay = MotionOverlayFrame(
      updatedAt: iso8601Formatter.string(from: now),
      personDetected: personDetected,
      poseLabel: snapshot.poseLabel.rawValue,
      motionScore: motionScore,
      personBox: uiBox.map(NormalizedRect.init),
      trail: trail,
      skeleton: skeleton
    )

    let detectorResult = detector.process(snapshot)
    snapshot.activityLabel = detectorResult.activityLabel

    DispatchQueue.main.async {
      self.onSnapshot?(snapshot)
      self.onOverlayFrame?(overlay)
      if let trigger = detectorResult.trigger {
        self.onActivityTrigger?(trigger)
      }
    }
  }

  private func motionScore(for box: CGRect?, now: Date) -> Double {
    defer {
      lastObservationBox = box
      lastObservationAt = now
    }

    guard let box,
          let lastObservationBox,
          let lastObservationAt else {
      return 0
    }

    let deltaTime = max(now.timeIntervalSince(lastObservationAt), 0.001)
    let deltaX = abs(box.midX - lastObservationBox.midX)
    let deltaY = abs(box.midY - lastObservationBox.midY)
    let deltaHeight = abs(box.height - lastObservationBox.height)
    return min(1.0, (deltaX + deltaY + deltaHeight) / deltaTime * 0.25)
  }

  private func visionRectToUICoordinates(_ rect: CGRect) -> CGRect {
    CGRect(
      x: rect.origin.x,
      y: 1 - rect.origin.y - rect.height,
      width: rect.width,
      height: rect.height
    )
  }

  private func visionPointToUICoordinates(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x, y: 1 - point.y)
  }

  private func postureSignals(from observation: VNHumanBodyPoseObservation?, box: CGRect?) -> PoseSignals {
    let aspectRatio = box.map { $0.height / max($0.width, 0.001) } ?? 0

    guard let observation,
          let points = try? observation.recognizedPoints(.all) else {
      let fallbackPose: PersonPoseLabel

      if aspectRatio >= 1.45 {
        fallbackPose = .transitional
      } else if aspectRatio > 0 {
        fallbackPose = .occupancyOnly
      } else {
        fallbackPose = .none
      }

      return PoseSignals(
        poseLabel: fallbackPose,
        uprightScore: min(max(aspectRatio / 1.7, 0), 1),
        legExtensionScore: min(max(aspectRatio / 2.0, 0), 1),
        aspectRatio: aspectRatio
      )
    }

    let minimumConfidence: VNConfidence = 0.2

    func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
      guard let recognized = points[joint],
            recognized.confidence >= minimumConfidence else {
        return nil
      }

      return visionPointToUICoordinates(recognized.location)
    }

    func averagedPoint(_ joints: [VNHumanBodyPoseObservation.JointName]) -> CGPoint? {
      let values = joints.compactMap(point)
      guard !values.isEmpty else {
        return nil
      }

      let total = values.reduce(CGPoint.zero) { partial, point in
        CGPoint(x: partial.x + point.x, y: partial.y + point.y)
      }

      return CGPoint(
        x: total.x / Double(values.count),
        y: total.y / Double(values.count)
      )
    }

    let shoulderCenter = averagedPoint([.leftShoulder, .rightShoulder, .neck])
    let hipCenter = averagedPoint([.leftHip, .rightHip, .root])
    let kneeCenter = averagedPoint([.leftKnee, .rightKnee])
    let ankleCenter = averagedPoint([.leftAnkle, .rightAnkle])

    let uprightScore = uprightScore(
      shoulders: shoulderCenter,
      hips: hipCenter,
      aspectRatio: aspectRatio
    )
    let legExtensionScore = legExtensionScore(
      hips: hipCenter,
      knees: kneeCenter,
      ankles: ankleCenter,
      aspectRatio: aspectRatio
    )
    let poseLabel = classifyPoseLabel(
      uprightScore: uprightScore,
      legExtensionScore: legExtensionScore,
      aspectRatio: aspectRatio
    )

    return PoseSignals(
      poseLabel: poseLabel,
      uprightScore: uprightScore,
      legExtensionScore: legExtensionScore,
      aspectRatio: aspectRatio
    )
  }

  private func uprightScore(
    shoulders: CGPoint?,
    hips: CGPoint?,
    aspectRatio: Double
  ) -> Double {
    guard let shoulders, let hips else {
      return min(max(aspectRatio / 1.7, 0), 1)
    }

    let deltaX = abs(shoulders.x - hips.x)
    let deltaY = max(hips.y - shoulders.y, 0.001)
    let alignmentScore = 1 - min(deltaX / deltaY, 1)
    let aspectBoost = min(max(aspectRatio / 1.8, 0), 1)
    return min(max(alignmentScore * 0.78 + aspectBoost * 0.22, 0), 1)
  }

  private func legExtensionScore(
    hips: CGPoint?,
    knees: CGPoint?,
    ankles: CGPoint?,
    aspectRatio: Double
  ) -> Double {
    guard let hips, let knees, let ankles else {
      return min(max(aspectRatio / 2.1, 0), 1)
    }

    let upperLength = hypot(hips.x - knees.x, hips.y - knees.y)
    let lowerLength = hypot(knees.x - ankles.x, knees.y - ankles.y)
    let fullLength = max(upperLength + lowerLength, 0.001)
    let verticalTravel = max(ankles.y - hips.y, 0)

    return min(max(verticalTravel / fullLength, 0), 1)
  }

  private func classifyPoseLabel(
    uprightScore: Double,
    legExtensionScore: Double,
    aspectRatio: Double
  ) -> PersonPoseLabel {
    if uprightScore >= 0.72, legExtensionScore >= 0.55, aspectRatio >= 1.15 {
      return .standing
    }

    if uprightScore >= 0.56, aspectRatio >= 0.95 {
      return .sittingUp
    }

    if aspectRatio < 0.95 || uprightScore < 0.4 {
      return .lyingDown
    }

    return .transitional
  }

  private func skeletonSegments(from observation: VNHumanBodyPoseObservation?) -> [MotionOverlaySegment] {
    guard let observation,
          let points = try? observation.recognizedPoints(.all) else {
      return []
    }

    let minimumConfidence: VNConfidence = 0.15

    return skeletonConnections.compactMap { startJoint, endJoint in
      guard let start = points[startJoint],
            let end = points[endJoint],
            start.confidence >= minimumConfidence,
            end.confidence >= minimumConfidence else {
        return nil
      }

      return MotionOverlaySegment(
        from: NormalizedPoint(visionPointToUICoordinates(start.location)),
        to: NormalizedPoint(visionPointToUICoordinates(end.location)),
        confidence: Double(min(start.confidence, end.confidence))
      )
    }
  }

  private func motionTrailPoints(for box: CGRect?, personDetected: Bool) -> [NormalizedPoint] {
    guard personDetected, let box else {
      motionTrail.removeAll()
      return []
    }

    let candidate = CGPoint(x: box.midX, y: box.midY)

    if let lastPoint = motionTrail.last {
      let distance = hypot(candidate.x - lastPoint.x, candidate.y - lastPoint.y)
      if distance >= 0.012 {
        motionTrail.append(candidate)
      }
    } else {
      motionTrail.append(candidate)
    }

    if motionTrail.count > 12 {
      motionTrail.removeFirst(motionTrail.count - 12)
    }

    return motionTrail.map(NormalizedPoint.init)
  }
}

extension SensorCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    onSampleBuffer?(sampleBuffer)
    processSampleBuffer(sampleBuffer)
  }
}
