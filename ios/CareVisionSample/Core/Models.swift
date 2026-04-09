import CoreGraphics
import Foundation

enum AppMode: String, CaseIterable, Identifiable {
  case sensor
  case caregiver

  var id: String { rawValue }

  var title: String {
    switch self {
    case .sensor:
      return "Sensor Mode"
    case .caregiver:
      return "Caregiver Mode"
    }
  }

  var subtitle: String {
    switch self {
    case .sensor:
      return "Room-side camera, Vision heuristics, and CV event publishing."
    case .caregiver:
      return "Realtime alert inbox, timeline updates, and rapid acknowledgement."
    }
  }
}

enum DemoRole: String, Codable {
  case sensor
  case caregiver
}

enum AlertState: String, Codable {
  case `new` = "new"
  case acknowledged
  case escalated
}

enum AlertPriority: String, Codable {
  case high
  case medium
}

enum CVEventType: String, Codable {
  case bedExitRisk = "bed_exit_risk"
  case personDetected = "person_detected"
  case motionSpike = "motion_spike"
  case noMotion = "no_motion"
  case uprightPoseDetected = "upright_pose_detected"
}

enum PersonPoseLabel: String, Codable {
  case none = "none"
  case occupancyOnly = "occupancy-only"
  case lyingDown = "lying-down"
  case sittingUp = "sitting-up"
  case standing = "standing"
  case transitional = "transitional"

  var title: String {
    rawValue.replacingOccurrences(of: "-", with: " ").capitalized
  }
}

enum BedsideActivityLabel: String, Codable {
  case clear = "clear"
  case inBed = "in-bed"
  case sittingUp = "sitting-up"
  case standingNearBed = "standing-near-bed"
  case exitingBed = "exiting-bed"

  var title: String {
    rawValue.replacingOccurrences(of: "-", with: " ").capitalized
  }
}

struct DemoSettings: Equatable {
  var baseURLString: String = "http://127.0.0.1:8787"
  var roomId: String = "room-demo-a"
  var sensorDisplayName: String = "Sensor iPhone"
  var caregiverDisplayName: String = "Caregiver iPhone"
  var sensorDeviceId: String = "sensor-device-01"
  var zone: ZoneConfiguration = .defaultBedside

  var signature: String {
    [
      baseURLString,
      roomId,
      sensorDisplayName,
      caregiverDisplayName,
      sensorDeviceId,
      zone.signature,
    ].joined(separator: "|")
  }
}

struct ZoneConfiguration: Equatable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  static let defaultBedside = ZoneConfiguration(
    x: 0.61,
    y: 0.18,
    width: 0.24,
    height: 0.58
  )

  var rect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }

  var signature: String {
    "\(x)-\(y)-\(width)-\(height)"
  }

  var clamped: ZoneConfiguration {
    let clampedWidth = min(max(width, 0.1), 0.5)
    let clampedHeight = min(max(height, 0.1), 0.8)
    let clampedX = min(max(x, 0), 1 - clampedWidth)
    let clampedY = min(max(y, 0), 1 - clampedHeight)
    return ZoneConfiguration(
      x: clampedX,
      y: clampedY,
      width: clampedWidth,
      height: clampedHeight
    )
  }
}

struct DemoSessionPayload: Codable {
  let id: String
  let displayName: String
  let role: DemoRole
}

struct DemoSessionResponse: Codable {
  let session: DemoSessionPayload
  let accessToken: String
}

struct StreamPermissions: Codable {
  let canPublish: Bool
  let canSubscribe: Bool
}

struct StreamTokenResponse: Codable {
  let roomId: String
  let participantName: String
  let livekitUrl: String
  let token: String
  let permissions: StreamPermissions
}

struct AlertItem: Identifiable, Codable, Equatable {
  let id: String
  let roomId: String
  let deviceId: String
  let eventType: CVEventType
  let title: String
  let body: String
  let priority: AlertPriority
  var state: AlertState
  let createdAt: String
  var updatedAt: String
  let sourceEventId: String
}

struct AlertListResponse: Codable {
  let alerts: [AlertItem]
}

struct AlertMutation: Codable {
  let id: String
  let state: AlertState
  let updatedAt: String
}

struct AlertMutationResponse: Codable {
  let alert: AlertMutation
}

struct TimelineEntry: Identifiable, Codable, Equatable {
  let id: String
  let kind: String
  let roomId: String
  let alertId: String
  let createdAt: String
  let summary: String
}

struct TimelineResponse: Codable {
  let entries: [TimelineEntry]
}

struct CVEventRequest: Encodable {
  let idempotencyKey: String
  let roomId: String
  let deviceId: String
  let eventType: CVEventType
  let confidence: Double
  let occurredAt: String
  let metadata: [String: String]
}

struct AlertReference: Codable {
  let id: String
  let state: AlertState
  let priority: AlertPriority
}

struct CVEventResponse: Codable {
  let accepted: Bool
  let eventId: String
  let alert: AlertReference?
}

struct HealthResponse: Codable {
  let status: String
  let service: String
  let time: String
}

struct SSEEvent {
  let event: String
  let data: String
}

struct NormalizedPoint: Codable, Equatable {
  let x: Double
  let y: Double

  init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  init(_ point: CGPoint) {
    x = point.x
    y = point.y
  }

  var cgPoint: CGPoint {
    CGPoint(x: x, y: y)
  }
}

struct NormalizedRect: Codable, Equatable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  init(_ rect: CGRect) {
    x = rect.origin.x
    y = rect.origin.y
    width = rect.width
    height = rect.height
  }

  var cgRect: CGRect {
    CGRect(x: x, y: y, width: width, height: height)
  }
}

struct MotionOverlaySegment: Codable, Equatable {
  let from: NormalizedPoint
  let to: NormalizedPoint
  let confidence: Double
}

struct MotionOverlayFrame: Codable, Equatable {
  let updatedAt: String
  let personDetected: Bool
  let poseLabel: String
  let motionScore: Double
  let personBox: NormalizedRect?
  let trail: [NormalizedPoint]
  let skeleton: [MotionOverlaySegment]

  static let empty = MotionOverlayFrame(
    updatedAt: "",
    personDetected: false,
    poseLabel: "none",
    motionScore: 0,
    personBox: nil,
    trail: [],
    skeleton: []
  )

  static func cleared(updatedAt: String) -> MotionOverlayFrame {
    MotionOverlayFrame(
      updatedAt: updatedAt,
      personDetected: false,
      poseLabel: "none",
      motionScore: 0,
      personBox: nil,
      trail: [],
      skeleton: []
    )
  }

  var isRenderable: Bool {
    personDetected || personBox != nil || !trail.isEmpty || !skeleton.isEmpty
  }
}

struct MotionOverlayPayload: Codable, Equatable {
  let roomId: String
  let deviceId: String
  let overlay: MotionOverlayFrame
}

struct MotionOverlayResponse: Codable {
  let accepted: Bool
}

enum DemoRealtimeTopic {
  static let motionOverlay = "motion-overlay"
}

struct DetectionSnapshot: Equatable {
  var personDetected: Bool
  var zoneOccupied: Bool
  var transitioning: Bool
  var confidence: Double
  var poseLabel: PersonPoseLabel
  var activityLabel: BedsideActivityLabel
  var motionScore: Double
  var uprightScore: Double
  var legExtensionScore: Double
  var aspectRatio: Double
  var lastUpdated: Date

  static let idle = DetectionSnapshot(
    personDetected: false,
    zoneOccupied: false,
    transitioning: false,
    confidence: 0,
    poseLabel: .none,
    activityLabel: .clear,
    motionScore: 0,
    uprightScore: 0,
    legExtensionScore: 0,
    aspectRatio: 0,
    lastUpdated: .distantPast
  )
}

enum CameraRuntimeState: Equatable {
  case idle
  case starting
  case live
  case fallback(String)
  case failed(String)

  var label: String {
    switch self {
    case .idle:
      return "Idle"
    case .starting:
      return "Starting"
    case .live:
      return "Live camera"
    case .fallback:
      return "Fallback"
    case .failed:
      return "Camera issue"
    }
  }

  var detail: String {
    switch self {
    case .idle:
      return "Sensor Mode is waiting for setup."
    case .starting:
      return "Requesting permission and warming the capture session."
    case .live:
      return "AVFoundation capture and Vision analysis are active."
    case let .fallback(message), let .failed(message):
      return message
    }
  }
}

struct BedExitTrigger {
  let eventType: CVEventType
  let confidence: Double
  let occurredAt: Date
  let poseLabel: PersonPoseLabel
  let activityLabel: BedsideActivityLabel
  let motionScore: Double
}

struct BedsideDetectorResult {
  let activityLabel: BedsideActivityLabel
  let trigger: BedExitTrigger?
}
