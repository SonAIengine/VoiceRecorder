import SwiftUI

/// M1a #4 — 시스템 상태 대시보드.
///
/// /api/autonomy/state 를 한 화면에 집계해서 보여준다:
/// - Runner 상태 (enabled, hard-stop, override)
/// - Collectors — 마지막 성공/실패/다음 실행, 에러 배지
/// - Subscriptions — 만료 임박/실패 경고
/// - Budget — 오늘 사용량 % 프로그레스 바
///
/// 이전엔 컨테이너 로그 + 수동 curl 이 필요했던 정보를 iOS 에서 바로 확인.
struct SystemStatusView: View {
    @State private var state: AutonomyState?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && state == nil {
                ProgressView("로딩 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage, state == nil {
                ContentUnavailableView(
                    "시스템 상태 로드 실패",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if let state {
                content(state)
            } else {
                ContentUnavailableView(
                    "데이터 없음",
                    systemImage: "tray",
                    description: Text("시스템 상태를 불러올 수 없습니다")
                )
            }
        }
        .navigationTitle("시스템 상태")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ state: AutonomyState) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                runnerCard(state)
                if let budget = state.budget {
                    budgetCard(budget)
                }
                if let collectors = state.collectors, !collectors.isEmpty {
                    collectorsCard(collectors)
                }
                if let subs = state.subscriptions, !subs.isEmpty {
                    subscriptionsCard(subs)
                }
            }
            .padding()
        }
    }

    // MARK: - Runner card

    private func runnerCard(_ state: AutonomyState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: runnerIcon(state))
                    .foregroundStyle(runnerColor(state))
                Text(runnerTitle(state))
                    .font(.headline)
                Spacer()
            }

            if state.hardStopped {
                Label {
                    Text("예산 150% 초과로 자동 정지됨. 예산 리셋 또는 수동 해제 필요.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                metric(label: "룰", value: "\(state.ruleCount)")
                metric(label: "관측", value: "\(state.seenCount)")
                metric(label: "dispatch", value: "\(state.dispatchedCount)")
            }

            if let skipped = state.skippedReasons, !skipped.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("건너뜀 사유")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(skipped.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                        HStack {
                            Text(item.key)
                                .font(.caption.monospaced())
                            Spacer()
                            Text("\(item.value)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func runnerIcon(_ state: AutonomyState) -> String {
        if state.hardStopped { return "exclamationmark.octagon.fill" }
        if state.enabled { return "play.circle.fill" }
        return "pause.circle.fill"
    }

    private func runnerColor(_ state: AutonomyState) -> Color {
        if state.hardStopped { return .red }
        if state.enabled { return .green }
        return .orange
    }

    private func runnerTitle(_ state: AutonomyState) -> String {
        if state.hardStopped { return "자율 루프 정지됨" }
        if state.enabled { return "자율 루프 동작 중" }
        return "자율 루프 비활성"
    }

    // MARK: - Budget card

    private func budgetCard(_ budget: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(badgeColor(for: budget.healthGrade))
                Text("예산")
                    .font(.headline)
                Spacer()
                if let used = budget.globalUsedUsd, let limit = budget.globalLimitUsd {
                    Text(String(format: "$%.2f / $%.2f", used, limit))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let pct = budget.hardStopPct {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Hard-stop 기준")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(pct))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(budgetPctColor(pct))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(budgetPctColor(pct))
                                .frame(width: max(4, geo.size.width * min(pct / 100, 1.0)))
                        }
                    }
                    .frame(height: 8)
                }
            }

            if let threshold = budget.hardStopThresholdUsd {
                Text("Hard-stop 임계값 $\(threshold, specifier: "%.2f")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func budgetPctColor(_ pct: Double) -> Color {
        if pct >= 100 { return .red }
        if pct >= 66 { return .orange }
        if pct >= 33 { return .yellow }
        return .green
    }

    // MARK: - Collectors card

    private func collectorsCard(_ collectors: [CollectorHealth]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.indigo)
                Text("수집기 (\(collectors.count))")
                    .font(.headline)
                Spacer()
            }

            ForEach(collectors) { c in
                collectorRow(c)
                if c.id != collectors.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func collectorRow(_ c: CollectorHealth) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(badgeColor(for: c.healthGrade))
                    .frame(width: 10, height: 10)
                Text(c.name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if c.successCount + c.failureCount > 0 {
                    Text("\(c.successCount)✓  \(c.failureCount)✗")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                if let last = c.lastSuccessAt {
                    Text("마지막 성공 \(relativeTime(from: last))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let next = c.nextRunAt {
                    Text("· 다음 \(relativeTime(from: next))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if let err = c.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subscriptions card

    private func subscriptionsCard(_ subs: [SubscriptionStatus]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.teal)
                Text("실시간 구독 (\(subs.count))")
                    .font(.headline)
                Spacer()
            }

            ForEach(subs) { s in
                subscriptionRow(s)
                if s.id != subs.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func subscriptionRow(_ s: SubscriptionStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(badgeColor(for: s.healthGrade))
                    .frame(width: 10, height: 10)
                Text(subscriptionLabel(s.id))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(s.status)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(badgeColor(for: s.healthGrade))
            }
            if let secs = s.expiresInSeconds {
                if secs < 0 {
                    Text("만료됨 \(formatDuration(-secs)) 경과")
                        .font(.caption2)
                        .foregroundStyle(.red)
                } else {
                    Text("만료까지 \(formatDuration(secs))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if s.consecutiveFailures > 0 {
                Text("연속 실패 \(s.consecutiveFailures)회")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
            if let err = s.lastRenewalError, !err.isEmpty {
                Text(err)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 4)
    }

    private func subscriptionLabel(_ id: String) -> String {
        switch id {
        case "outlook_mail": return "Outlook 메일"
        case "teams_chats": return "Teams 채팅"
        default: return id
        }
    }

    // MARK: - Bits

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func badgeColor(for grade: HealthGrade) -> Color {
        switch grade {
        case .healthy: return .green
        case .warning: return .orange
        case .failing: return .red
        case .unknown: return .gray
        }
    }

    private func relativeTime(from iso: String) -> String {
        guard let date = parseIso(iso) else { return "?" }
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 0 {
            return "\(formatDuration(-diff)) 뒤"
        }
        if diff < 60 { return "\(diff)초 전" }
        return "\(formatDuration(diff)) 전"
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)초" }
        let m = seconds / 60
        if m < 60 { return "\(m)분" }
        let h = m / 60
        if h < 24 { return "\(h)시간" }
        return "\(h / 24)일"
    }

    private func parseIso(_ s: String) -> Date? {
        let fmt1 = ISO8601DateFormatter()
        fmt1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt1.date(from: s) { return d }
        let fmt2 = ISO8601DateFormatter()
        fmt2.formatOptions = [.withInternetDateTime]
        return fmt2.date(from: s)
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            state = try await HarnessService.fetchAutonomyState()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
