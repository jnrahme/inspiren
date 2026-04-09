import Foundation

enum APIClientError: LocalizedError {
  case invalidBaseURL(String)
  case invalidResponse
  case server(statusCode: Int, message: String)

  var errorDescription: String? {
    switch self {
    case let .invalidBaseURL(baseURL):
      return "Invalid backend URL: \(baseURL)"
    case .invalidResponse:
      return "The backend returned an invalid response."
    case let .server(statusCode, message):
      return "Backend error \(statusCode): \(message)"
    }
  }
}

struct APIClient {
  let baseURL: URL

  private let decoder: JSONDecoder = JSONDecoder()
  private let encoder: JSONEncoder = JSONEncoder()

  init(baseURLString: String) throws {
    guard let baseURL = URL(string: baseURLString) else {
      throw APIClientError.invalidBaseURL(baseURLString)
    }
    self.baseURL = baseURL
  }

  func health() async throws -> HealthResponse {
    try await request(path: "/health")
  }

  func createDemoSession(displayName: String, role: DemoRole) async throws -> DemoSessionResponse {
    try await request(
      path: "/auth/demo-session",
      method: "POST",
      body: ["displayName": displayName, "role": role.rawValue]
    )
  }

  func fetchStreamToken(
    accessToken: String,
    roomId: String,
    participantName: String,
    role: DemoRole
  ) async throws -> StreamTokenResponse {
    try await request(
      path: "/stream/token",
      method: "POST",
      bearerToken: accessToken,
      body: [
        "roomId": roomId,
        "participantName": participantName,
        "role": role.rawValue,
      ]
    )
  }

  func sendCVEvent(accessToken: String, payload: CVEventRequest) async throws -> CVEventResponse {
    try await request(
      path: "/events/cv",
      method: "POST",
      bearerToken: accessToken,
      body: payload
    )
  }

  func sendMotionOverlay(accessToken: String, payload: MotionOverlayPayload) async throws -> MotionOverlayResponse {
    try await request(
      path: "/overlay/frames",
      method: "POST",
      bearerToken: accessToken,
      body: payload
    )
  }

  func fetchAlerts(accessToken: String, roomId: String) async throws -> [AlertItem] {
    var components = URLComponents(url: baseURL.appendingPathComponent("alerts"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "roomId", value: roomId)]
    let url = try components?.validatedURL() ?? { throw APIClientError.invalidResponse }()
    let response: AlertListResponse = try await request(url: url, bearerToken: accessToken)
    return response.alerts
  }

  func fetchTimeline(accessToken: String, roomId: String) async throws -> [TimelineEntry] {
    var components = URLComponents(url: baseURL.appendingPathComponent("timeline"), resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "roomId", value: roomId)]
    let url = try components?.validatedURL() ?? { throw APIClientError.invalidResponse }()
    let response: TimelineResponse = try await request(url: url, bearerToken: accessToken)
    return response.entries
  }

  func acknowledgeAlert(accessToken: String, alertId: String, actorName: String) async throws -> AlertMutation {
    let response: AlertMutationResponse = try await request(
      path: "/alerts/\(alertId)/acknowledge",
      method: "POST",
      bearerToken: accessToken,
      body: ["actorName": actorName]
    )
    return response.alert
  }

  func eventsStreamURL() -> URL {
    baseURL.appendingPathComponent("events/stream")
  }

  private func request<Response: Decodable>(
    path: String,
    method: String = "GET",
    bearerToken: String? = nil
  ) async throws -> Response {
    try await request(
      url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
      method: method,
      bearerToken: bearerToken
    )
  }

  private func request<Response: Decodable, Body: Encodable>(
    path: String,
    method: String,
    bearerToken: String? = nil,
    body: Body
  ) async throws -> Response {
    try await request(
      url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
      method: method,
      bearerToken: bearerToken,
      body: body
    )
  }

  private func request<Response: Decodable>(
    url: URL,
    method: String = "GET",
    bearerToken: String? = nil
  ) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let bearerToken {
      request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    return try await perform(request)
  }

  private func request<Response: Decodable, Body: Encodable>(
    url: URL,
    method: String,
    bearerToken: String? = nil,
    body: Body
  ) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let bearerToken {
      request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
    request.httpBody = try encoder.encode(body)
    return try await perform(request)
  }

  private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw APIClientError.invalidResponse
    }

    guard (200 ..< 300).contains(httpResponse.statusCode) else {
      let message = String(data: data, encoding: .utf8) ?? "Unknown backend error"
      throw APIClientError.server(statusCode: httpResponse.statusCode, message: message)
    }

    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      throw APIClientError.invalidResponse
    }
  }
}

private extension URLComponents {
  func validatedURL() throws -> URL {
    guard let url else {
      throw APIClientError.invalidResponse
    }
    return url
  }
}
