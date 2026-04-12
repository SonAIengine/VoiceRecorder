import Foundation

// MARK: - Models

struct HarnessStats: Codable {
    let totalNodes: Int
    let kindSession: Int
    let kindToolCall: Int
    let kindObservation: Int
    let kindLesson: Int
    let kindConcept: Int
    let cacheHitRate: Double
    let cacheSize: Int

    enum CodingKeys: String, CodingKey {
        case totalNodes = "total_nodes"
        case kindSession = "kind_session"
        case kindToolCall = "kind_tool_call"
        case kindObservation = "kind_observation"
        case kindLesson = "kind_lesson"
        case kindConcept = "kind_concept"
        case cacheHitRate = "cache_hit_rate"
        case cacheSize = "cache_size"
    }
}

struct AgentSession: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let agentId: String
    let createdAt: Double
    let updatedAt: Double?
    let successCount: Int
    let failureCount: Int

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case agentId = "agent_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case successCount = "success_count"
        case failureCount = "failure_count"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }

    var agentDisplayName: String {
        if agentId.starts(with: "collector:") {
            return agentId.replacingOccurrences(of: "collector:", with: "")
                .capitalized + " 수집"
        }
        return agentId.replacingOccurrences(of: "agent:", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var agentIcon: String {
        switch agentId {
        case let id where id.contains("github"): return "cat"
        case let id where id.contains("gitlab"): return "shippingbox"
        case let id where id.contains("kakao"): return "message"
        case let id where id.contains("ms365"), let id where id.contains("outlook"): return "envelope"
        case let id where id.contains("summary"): return "doc.text.magnifyingglass"
        case let id where id.contains("teams"): return "person.3"
        case let id where id.contains("calendar"): return "calendar"
        default: return "gearshape.2"
        }
    }
}

struct AgentSessionDetail: Codable {
    let id: String
    let title: String
    let description: String
    let agentId: String
    let createdAt: Double
    let successCount: Int
    let failureCount: Int
    let timeline: [TimelineEvent]

    enum CodingKeys: String, CodingKey {
        case id, title, description, timeline
        case agentId = "agent_id"
        case createdAt = "created_at"
        case successCount = "success_count"
        case failureCount = "failure_count"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }
}

struct TimelineEvent: Codable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let content: String
    let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id, kind, title, content
        case createdAt = "created_at"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }

    var kindIcon: String {
        switch kind {
        case "tool_call": return "wrench.and.screwdriver"
        case "observation": return "eye"
        case "session": return "play.circle"
        default: return "circle"
        }
    }
}

struct FeedbackLesson: Codable, Identifiable {
    let id: String
    let title: String
    let content: String
    let tags: [String]
    let sessionId: String
    let rating: String?
    let createdAt: Double

    enum CodingKeys: String, CodingKey {
        case id, title, content, tags, rating
        case sessionId = "session_id"
        case createdAt = "created_at"
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt)
    }

    var ratingIcon: String {
        switch rating {
        case "good": return "hand.thumbsup.fill"
        case "bad": return "hand.thumbsdown.fill"
        default: return "minus.circle"
        }
    }

    var ratingColor: String {
        switch rating {
        case "good": return "green"
        case "bad": return "red"
        default: return "secondary"
        }
    }
}

// MARK: - Autonomy state (M1a #2/#3/#5)

struct AutonomyState: Codable {
    let enabled: Bool
    let envEnabled: Bool
    let overrideEnabled: Bool?
    let hardStopped: Bool
    let canDispatch: Bool
    let ruleCount: Int
    let seenCount: Int
    let dispatchedCount: Int
    let perSourceCount: [String: Int]?
    let skippedReasons: [String: Int]?
    // M1a #3/#5 — observability
    let collectors: [CollectorHealth]?
    let subscriptions: [SubscriptionStatus]?
    let budget: BudgetStatus?

    enum CodingKeys: String, CodingKey {
        case enabled
        case envEnabled = "env_enabled"
        case overrideEnabled = "override_enabled"
        case hardStopped = "hard_stopped"
        case canDispatch = "can_dispatch"
        case ruleCount = "rule_count"
        case seenCount = "seen_count"
        case dispatchedCount = "dispatched_count"
        case perSourceCount = "per_source_count"
        case skippedReasons = "skipped_reasons"
        case collectors
        case subscriptions
        case budget
    }
}

struct CollectorHealth: Codable, Identifiable {
    let id: String
    let sourceName: String
    let name: String
    let nextRunAt: String?
    let lastSuccessAt: String?
    let lastFailureAt: String?
    let lastError: String?
    let successCount: Int
    let failureCount: Int
    let newEntriesTotal: Int

    enum CodingKeys: String, CodingKey {
        case id
        case sourceName = "source_name"
        case name
        case nextRunAt = "next_run_at"
        case lastSuccessAt = "last_success_at"
        case lastFailureAt = "last_failure_at"
        case lastError = "last_error"
        case successCount = "success_count"
        case failureCount = "failure_count"
        case newEntriesTotal = "new_entries_total"
    }

    /// 상태 등급 — 뷰에서 색 배지로 매핑.
    var healthGrade: HealthGrade {
        if lastError != nil {
            return .failing
        }
        if lastSuccessAt == nil {
            return .unknown  // 아직 한 번도 안 돌았음
        }
        return .healthy
    }
}

struct SubscriptionStatus: Codable, Identifiable {
    let id: String
    let subscriptionIdPrefix: String?
    let resource: String?
    let expiration: String?
    let expiresInSeconds: Int?
    let expired: Bool
    let createdAt: String?
    let status: String  // healthy | warning | failing | expired
    let consecutiveFailures: Int
    let lastRenewalAt: String?
    let lastRenewalError: String?

    enum CodingKeys: String, CodingKey {
        case id
        case subscriptionIdPrefix = "subscription_id_prefix"
        case resource
        case expiration
        case expiresInSeconds = "expires_in_seconds"
        case expired
        case createdAt = "created_at"
        case status
        case consecutiveFailures = "consecutive_failures"
        case lastRenewalAt = "last_renewal_at"
        case lastRenewalError = "last_renewal_error"
    }

    var healthGrade: HealthGrade {
        switch status {
        case "healthy": return .healthy
        case "warning": return .warning
        case "failing", "expired": return .failing
        default: return .unknown
        }
    }
}

struct BudgetStatus: Codable {
    let available: Bool
    let globalUsedUsd: Double?
    let globalLimitUsd: Double?
    let globalPct: Double?
    let hardStopThresholdUsd: Double?
    let hardStopPct: Double?
    let hardStopMultiplier: Double?

    enum CodingKeys: String, CodingKey {
        case available
        case globalUsedUsd = "global_used_usd"
        case globalLimitUsd = "global_limit_usd"
        case globalPct = "global_pct"
        case hardStopThresholdUsd = "hard_stop_threshold_usd"
        case hardStopPct = "hard_stop_pct"
        case hardStopMultiplier = "hard_stop_multiplier"
    }

    var healthGrade: HealthGrade {
        guard let pct = hardStopPct else { return .unknown }
        if pct >= 100 { return .failing }    // hard-stop 걸림
        if pct >= 66 { return .warning }     // hard-stop 의 2/3 이상
        if pct >= 33 { return .warning }     // 1/3 이상 — 주의
        return .healthy
    }
}

enum HealthGrade: String {
    case healthy
    case warning
    case failing
    case unknown
}

// MARK: - Rejection metrics (M1a #6/#7)

struct RejectionMetrics: Codable {
    let window: MetricsWindow
    let totalResolved: Int
    let approved: Int
    let rejected: Int
    let modified: Int
    let pendingInWindow: Int
    let rejectionRate: Double?
    let editRate: Double?
    let bySource: [String: MetricsBreakdown]
    let byOrigin: [String: MetricsBreakdown]

    enum CodingKeys: String, CodingKey {
        case window
        case totalResolved = "total_resolved"
        case approved
        case rejected
        case modified
        case pendingInWindow = "pending_in_window"
        case rejectionRate = "rejection_rate"
        case editRate = "edit_rate"
        case bySource = "by_source"
        case byOrigin = "by_origin"
    }
}

struct MetricsWindow: Codable {
    let days: Int
    let start: String
    let end: String
}

struct MetricsBreakdown: Codable {
    let total: Int
    let resolved: Int
    let approved: Int
    let rejected: Int
    let modified: Int
    let pending: Int
    let rejectionRate: Double?

    enum CodingKeys: String, CodingKey {
        case total
        case resolved
        case approved
        case rejected
        case modified
        case pending
        case rejectionRate = "rejection_rate"
    }
}

// MARK: - Service

enum HarnessService {
    static var serverURL: String {
        ChunkUploader.shared.currentServerURL
    }

    static func fetchStats() async throws -> HarnessStats {
        let data = try await get("api/harness/stats")
        return try JSONDecoder().decode(HarnessStats.self, from: data)
    }

    // MARK: - Autonomy

    static func fetchAutonomyState() async throws -> AutonomyState {
        let data = try await get("api/autonomy/state")
        return try JSONDecoder().decode(AutonomyState.self, from: data)
    }

    /// value: true=강제 on, false=강제 off, nil=override 해제(env 기본값으로).
    static func setAutonomyEnabled(_ value: Bool?) async throws -> AutonomyState {
        let body: [String: Any?] = ["enabled": value]
        let data = try await post("api/autonomy/toggle", body: body)
        return try JSONDecoder().decode(AutonomyState.self, from: data)
    }

    // MARK: - Metrics (M1a #6/#7)

    static func fetchRejectionMetrics(days: Int = 7) async throws -> RejectionMetrics {
        let data = try await get("api/metrics/rejection_rate?days=\(days)")
        return try JSONDecoder().decode(RejectionMetrics.self, from: data)
    }

    static func fetchSessions(limit: Int = 30, agentId: String? = nil) async throws -> [AgentSession] {
        var path = "api/harness/sessions?limit=\(limit)"
        if let agentId {
            path += "&agent_id=\(agentId)"
        }
        let data = try await get(path)
        struct Response: Codable { let sessions: [AgentSession]; let total: Int }
        return try JSONDecoder().decode(Response.self, from: data).sessions
    }

    static func fetchSessionDetail(id: String) async throws -> AgentSessionDetail {
        let data = try await get("api/harness/sessions/\(id)")
        return try JSONDecoder().decode(AgentSessionDetail.self, from: data)
    }

    static func fetchFeedback(limit: Int = 20) async throws -> [FeedbackLesson] {
        let data = try await get("api/harness/feedback?limit=\(limit)")
        struct Response: Codable { let lessons: [FeedbackLesson]; let total: Int }
        return try JSONDecoder().decode(Response.self, from: data).lessons
    }

    // MARK: - Private

    private static func get(_ path: String) async throws -> Data {
        // path 에 쿼리스트링이 포함될 수 있으므로 appendingPathComponent 대신
        // 직접 문자열 합산 후 URL(string:) 사용 (appendingPathComponent 는 ? 를 인코딩함)
        let base = serverURL.hasSuffix("/") ? serverURL : serverURL + "/"
        guard let url = URL(string: base + path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func post(_ path: String, body: [String: Any?]) async throws -> Data {
        guard let url = URL(string: serverURL)?.appendingPathComponent(path) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // null 값을 JSONSerialization 이 해석할 수 있도록 NSNull 로 치환
        var serializable: [String: Any] = [:]
        for (k, v) in body {
            serializable[k] = v ?? NSNull()
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: serializable)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
