import Foundation

final class SSEClient {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func events(url: URL, bearerToken: String) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode) else {
          throw APIClientError.invalidResponse
        }

        var currentEvent = "message"
        var dataLines: [String] = []

        func flush() {
          guard !dataLines.isEmpty else {
            currentEvent = "message"
            return
          }

          continuation.yield(
            SSEEvent(event: currentEvent, data: dataLines.joined(separator: "\n"))
          )
          currentEvent = "message"
          dataLines.removeAll()
        }

        for try await line in bytes.lines {
          if Task.isCancelled {
            break
          }

          if line.isEmpty {
            flush()
            continue
          }

          if line.hasPrefix(":") {
            continue
          }

          if line.hasPrefix("event:") {
            currentEvent = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            continue
          }

          if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
          }
        }

        flush()
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
