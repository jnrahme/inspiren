import Foundation

@MainActor
final class CaregiverModeViewModel: ObservableObject {
  @Published private(set) var alerts: [AlertItem] = []
  @Published private(set) var timeline: [TimelineEntry] = []
  @Published private(set) var overlay: MotionOverlayFrame = .empty
  @Published private(set) var connectionSummary = "Not connected"
  @Published private(set) var streamSummary = "No subscriber token requested yet."
  @Published private(set) var errorMessage: String?
  let streamManager: LiveKitRoomManager

  private let settings: DemoSettings
  private let sseClient = SSEClient()
  private let decoder = JSONDecoder()

  private var apiClient: APIClient?
  private var accessToken: String?
  private var streamTask: Task<Void, Never>?
  private var hasStarted = false

  init(settings: DemoSettings) {
    self.settings = settings
    streamManager = LiveKitRoomManager(
      settings: settings,
      role: .caregiver,
      displayName: settings.caregiverDisplayName,
      participantName: "caregiver-\(UUID().uuidString.prefix(6))"
    )
  }

  deinit {
    streamTask?.cancel()
  }

  func startIfNeeded() async {
    guard !hasStarted else { return }
    hasStarted = true
    await connect()
  }

  func reconnect() async {
    streamTask?.cancel()
    await streamManager.disconnect()
    overlay = .empty
    hasStarted = true
    await connect()
  }

  func stop() {
    streamTask?.cancel()
    overlay = .empty
    Task {
      await streamManager.disconnect()
    }
    hasStarted = false
  }

  func acknowledge(_ alert: AlertItem) async {
    guard let apiClient, let accessToken else { return }

    do {
      let mutation = try await apiClient.acknowledgeAlert(
        accessToken: accessToken,
        alertId: alert.id,
        actorName: settings.caregiverDisplayName
      )
      if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
        alerts[index].state = mutation.state
        alerts[index].updatedAt = mutation.updatedAt
      }
      timeline = try await apiClient.fetchTimeline(accessToken: accessToken, roomId: settings.roomId)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func connect() async {
    do {
      let client = try APIClient(baseURLString: settings.baseURLString)
      _ = try await client.health()
      let session = try await client.createDemoSession(
        displayName: settings.caregiverDisplayName,
        role: .caregiver
      )
      let stream = try await client.fetchStreamToken(
        accessToken: session.accessToken,
        roomId: settings.roomId,
        participantName: "caregiver-\(UUID().uuidString.prefix(6))",
        role: .caregiver
      )
      let alerts = try await client.fetchAlerts(accessToken: session.accessToken, roomId: settings.roomId)
      let timeline = try await client.fetchTimeline(accessToken: session.accessToken, roomId: settings.roomId)

      apiClient = client
      accessToken = session.accessToken
      overlay = .empty
      streamSummary = "Subscriber token ready for \(stream.roomId) at \(stream.livekitUrl)"
      connectionSummary = "Connecting to realtime stream"
      errorMessage = nil
      self.alerts = alerts
      self.timeline = timeline

      startRealtime(client: client, accessToken: session.accessToken)
      await streamManager.connectSubscriber()
    } catch {
      streamSummary = "Subscriber token unavailable."
      connectionSummary = "Disconnected"
      errorMessage = error.localizedDescription
    }
  }

  private func startRealtime(client: APIClient, accessToken: String) {
    streamTask?.cancel()
    streamTask = Task { [weak self] in
      guard let self else { return }

      do {
        let stream = sseClient.events(url: client.eventsStreamURL(), bearerToken: accessToken)
        for try await event in stream {
          if Task.isCancelled { return }
          await handle(event)
        }
      } catch {
        if Task.isCancelled { return }
        errorMessage = error.localizedDescription
        connectionSummary = "Realtime disconnected"
      }
    }
  }

  private func handle(_ event: SSEEvent) async {
    switch event.event {
    case "connection.ready":
      connectionSummary = "Realtime connected"

    case "alert.created":
      if let data = event.data.data(using: .utf8),
         let alert = try? decoder.decode(AlertItem.self, from: data) {
        upsert(alert)
      }

    case "alert.updated":
      if let data = event.data.data(using: .utf8),
         let alert = try? decoder.decode(AlertItem.self, from: data) {
        upsert(alert)
      }

    case "timeline.created":
      if let data = event.data.data(using: .utf8),
         let entry = try? decoder.decode(TimelineEntry.self, from: data) {
        upsert(entry)
      }

    case "overlay.updated":
      if let data = event.data.data(using: .utf8),
         let payload = try? decoder.decode(MotionOverlayPayload.self, from: data),
         payload.roomId == settings.roomId {
        overlay = payload.overlay
      }

    default:
      break
    }
  }

  private func upsert(_ alert: AlertItem) {
    if let index = alerts.firstIndex(where: { $0.id == alert.id }) {
      alerts[index] = alert
    } else {
      alerts.insert(alert, at: 0)
    }
    alerts.sort { $0.createdAt > $1.createdAt }
  }

  private func upsert(_ entry: TimelineEntry) {
    if let index = timeline.firstIndex(where: { $0.id == entry.id }) {
      timeline[index] = entry
    } else {
      timeline.insert(entry, at: 0)
    }
    timeline.sort { $0.createdAt > $1.createdAt }
  }
}
