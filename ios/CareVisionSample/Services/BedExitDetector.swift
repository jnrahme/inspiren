import Foundation

final class BedExitDetector {
  private let uprightPersistenceWindow: TimeInterval = 0.8
  private let bedExitPersistenceWindow: TimeInterval = 0.6
  private let uprightCooldownWindow: TimeInterval = 8.0
  private let bedExitCooldownWindow: TimeInterval = 10.0
  private let clearWindow: TimeInterval = 3.0
  private let recentBedsideWindow: TimeInterval = 1.8

  private var activityLabel: BedsideActivityLabel = .clear
  private var activitySince: Date?
  private var uprightCooldownUntil: Date?
  private var bedExitCooldownUntil: Date?
  private var clearSince: Date?
  private var lastZoneOccupiedAt: Date?
  private var lastStandingAt: Date?
  private var uprightTriggeredInCurrentStage = false
  private var bedExitTriggeredInCurrentStage = false

  func reset() {
    activityLabel = .clear
    activitySince = nil
    uprightCooldownUntil = nil
    bedExitCooldownUntil = nil
    clearSince = nil
    lastZoneOccupiedAt = nil
    lastStandingAt = nil
    uprightTriggeredInCurrentStage = false
    bedExitTriggeredInCurrentStage = false
  }

  func process(_ snapshot: DetectionSnapshot) -> BedsideDetectorResult {
    let now = snapshot.lastUpdated

    if snapshot.zoneOccupied {
      lastZoneOccupiedAt = now
    }
    if snapshot.poseLabel == .standing {
      lastStandingAt = now
    }

    let nextActivity = classifyActivity(for: snapshot, now: now)

    if nextActivity != activityLabel {
      activityLabel = nextActivity
      activitySince = now
      uprightTriggeredInCurrentStage = false
      bedExitTriggeredInCurrentStage = false
    } else if activitySince == nil {
      activitySince = now
    }

    let persistedFor = activitySince.map { now.timeIntervalSince($0) } ?? 0
    var trigger: BedExitTrigger?

    switch activityLabel {
    case .standingNearBed:
      clearSince = nil
      if !uprightTriggeredInCurrentStage,
         uprightCooldownUntil.map({ now >= $0 }) ?? true,
         persistedFor >= uprightPersistenceWindow {
        uprightTriggeredInCurrentStage = true
        uprightCooldownUntil = now.addingTimeInterval(uprightCooldownWindow)
        trigger = BedExitTrigger(
          eventType: .uprightPoseDetected,
          confidence: snapshot.confidence,
          occurredAt: now,
          poseLabel: snapshot.poseLabel,
          activityLabel: activityLabel,
          motionScore: snapshot.motionScore
        )
      }

    case .exitingBed:
      clearSince = nil
      if !bedExitTriggeredInCurrentStage,
         bedExitCooldownUntil.map({ now >= $0 }) ?? true,
         persistedFor >= bedExitPersistenceWindow {
        bedExitTriggeredInCurrentStage = true
        bedExitCooldownUntil = now.addingTimeInterval(bedExitCooldownWindow)
        uprightCooldownUntil = now.addingTimeInterval(uprightCooldownWindow)
        trigger = BedExitTrigger(
          eventType: .bedExitRisk,
          confidence: max(snapshot.confidence, snapshot.uprightScore),
          occurredAt: now,
          poseLabel: snapshot.poseLabel,
          activityLabel: activityLabel,
          motionScore: snapshot.motionScore
        )
      }

    case .clear:
      if clearSince == nil {
        clearSince = now
      }
      if let clearSince, now.timeIntervalSince(clearSince) >= clearWindow {
        lastZoneOccupiedAt = nil
        lastStandingAt = nil
      }

    case .inBed, .sittingUp:
      clearSince = nil
    }

    return BedsideDetectorResult(
      activityLabel: activityLabel,
      trigger: trigger
    )
  }

  private func classifyActivity(for snapshot: DetectionSnapshot, now: Date) -> BedsideActivityLabel {
    guard snapshot.personDetected else {
      return .clear
    }

    if snapshot.zoneOccupied {
      switch snapshot.poseLabel {
      case .standing:
        return .standingNearBed
      case .sittingUp, .transitional:
        return .sittingUp
      case .none, .occupancyOnly, .lyingDown:
        return .inBed
      }
    }

    let recentlyInZone = lastZoneOccupiedAt.map { now.timeIntervalSince($0) <= recentBedsideWindow } ?? false
    let recentlyStanding = lastStandingAt.map { now.timeIntervalSince($0) <= recentBedsideWindow } ?? false

    if recentlyInZone && (recentlyStanding || snapshot.poseLabel == .standing || snapshot.uprightScore >= 0.7) {
      return .exitingBed
    }

    return .clear
  }
}
