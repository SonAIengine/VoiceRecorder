import Foundation
import Network

/// 오프라인 큐 — 네트워크 끊김 시 승인/거절/명령을 로컬 저장, 복구 시 자동 전송.
///
/// 사용법:
/// - `OfflineQueue.shared.isOnline` 으로 현재 연결 상태 확인
/// - 네트워크 에러 catch 시 `enqueue(...)` 로 큐에 추가
/// - 연결 복구 → 자동 `drain()` → 완료 후 `onDrained` 콜백
@Observable
final class OfflineQueue {
    static let shared = OfflineQueue()

    private(set) var isOnline = true
    private(set) var pendingActions: [QueuedAction] = []
    private(set) var isDraining = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "sonlife.offline-queue")
    private let fileURL: URL

    private init() {
        fileURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("offline_queue.json")
        loadFromDisk()

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if wasOffline && self.isOnline {
                    await self.drain()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    var count: Int { pendingActions.count }

    // MARK: - Enqueue

    func enqueue(_ action: QueuedAction) {
        pendingActions.append(action)
        saveToDisk()
    }

    // MARK: - Drain

    @MainActor
    func drain() async {
        guard !isDraining, !pendingActions.isEmpty else { return }
        isDraining = true
        defer { isDraining = false }

        var remaining: [QueuedAction] = []
        for action in pendingActions {
            do {
                try await execute(action)
            } catch {
                if Self.isNetworkError(error) {
                    remaining.append(action)
                }
                // 4xx/5xx 등 서버 에러 → 재시도 불가, 버림
            }
        }
        pendingActions = remaining
        saveToDisk()
    }

    // MARK: - Execute

    private func execute(_ action: QueuedAction) async throws {
        switch action.kind {
        case .approve:
            guard let token = action.token else { return }
            _ = try await OrchestratorAPI.approve(token: token, modifiedArgs: action.modifiedArgs)
        case .reject:
            guard let token = action.token else { return }
            _ = try await OrchestratorAPI.reject(token: token, reason: action.reason)
        case .command:
            guard let input = action.input else { return }
            _ = try await OrchestratorAPI.dispatch(input: input)
        }
    }

    // MARK: - Network Error Detection

    static func isNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
        ].contains(nsError.code)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        pendingActions = (try? JSONDecoder().decode([QueuedAction].self, from: data)) ?? []
    }

    private func saveToDisk() {
        guard let data = try? JSONEncoder().encode(pendingActions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Queued Action

struct QueuedAction: Codable, Identifiable {
    let id: String
    let kind: ActionKind
    let token: String?
    let modifiedArgs: ApprovalArgs?
    let reason: String?
    let input: String?
    let createdAt: Date

    enum ActionKind: String, Codable {
        case approve, reject, command
    }

    var kindLabel: String {
        switch kind {
        case .approve: return "승인"
        case .reject:  return "거절"
        case .command: return "명령"
        }
    }

    static func approve(token: String, modifiedArgs: ApprovalArgs? = nil) -> QueuedAction {
        QueuedAction(
            id: UUID().uuidString, kind: .approve,
            token: token, modifiedArgs: modifiedArgs,
            reason: nil, input: nil, createdAt: Date()
        )
    }

    static func reject(token: String, reason: String?) -> QueuedAction {
        QueuedAction(
            id: UUID().uuidString, kind: .reject,
            token: token, modifiedArgs: nil,
            reason: reason, input: nil, createdAt: Date()
        )
    }

    static func command(input: String) -> QueuedAction {
        QueuedAction(
            id: UUID().uuidString, kind: .command,
            token: nil, modifiedArgs: nil,
            reason: nil, input: input, createdAt: Date()
        )
    }
}
