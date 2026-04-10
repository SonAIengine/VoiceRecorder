import Foundation

/// C-6 Server-Sent Events 클라이언트.
///
/// iOS의 URLSession.bytes(for:)로 라인 단위 스트림을 읽어
/// SSE 포맷(`event: <name>\ndata: <json>\n\n`)을 파싱.
///
/// 사용:
/// ```swift
/// let stream = SSEClient.stream(url: URL(...)!)
/// for try await event in stream {
///     switch event.type {
///     case "tool.called": ...
///     case "session.completed": break
///     }
/// }
/// ```
enum SSEClient {

    struct Event {
        let type: String
        let data: [String: Any]
    }

    enum SSEError: Error {
        case badURL
        case badResponse(Int)
        case cancelled
    }

    /// 지정 URL에서 SSE 이벤트 스트림을 열고 AsyncStream으로 반환.
    static func stream(url: URL) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 600  // 10분

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: SSEError.badResponse(code))
                        return
                    }

                    var currentEventType: String?
                    var currentDataLines: [String] = []

                    for try await line in bytes.lines {
                        // SSE format:
                        // event: <type>
                        // data: <json>
                        // (empty line terminates event)
                        if line.isEmpty {
                            // 이벤트 경계 — 조립해서 방출
                            if let type = currentEventType {
                                let dataStr = currentDataLines.joined(separator: "\n")
                                let dict = parseJSONDict(dataStr) ?? [:]
                                continuation.yield(Event(type: type, data: dict))
                                // 종료 이벤트면 스트림 닫기
                                if type == "end" || type == "session.completed"
                                    || type == "session.failed" || type == "session.suspended" {
                                    continuation.finish()
                                    return
                                }
                            }
                            currentEventType = nil
                            currentDataLines = []
                            continue
                        }
                        if line.hasPrefix("event: ") {
                            currentEventType = String(line.dropFirst("event: ".count))
                        } else if line.hasPrefix("data: ") {
                            currentDataLines.append(String(line.dropFirst("data: ".count)))
                        }
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: SSEError.cancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func parseJSONDict(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
