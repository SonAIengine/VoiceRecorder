import SwiftUI

/// Phase A 에이전트 실행 기록 (orchestrator) — /api/sessions
///
/// 기존 AgentDashboardView의 HarnessService 세션과는 별개. 이쪽은 Phase A
/// orchestrator가 만든 세션 (CommandInputView로 발행한 명령들).
struct OrchestratorSessionHistoryView: View {
    @State private var sessions: [OrchestratorSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedSession: OrchestratorSession?

    var body: some View {
        Group {
            if isLoading && sessions.isEmpty {
                ProgressView("불러오는 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage, sessions.isEmpty {
                ContentUnavailableView {
                    Label("불러오기 실패", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error).font(.footnote)
                } actions: {
                    Button("재시도") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "실행 기록 없음",
                    systemImage: "tray",
                    description: Text("에이전트에 명령을 보내면 여기에 기록됩니다")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            OrchestratorSessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("에이전트 실행 기록")
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
        .sheet(item: $selectedSession) { session in
            OrchestratorSessionDetailSheet(session: session)
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            sessions = try await OrchestratorAPI.fetchSessions(limit: 50)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Row

private struct OrchestratorSessionRow: View {
    let session: OrchestratorSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.agentName.capitalized)
                        .font(.subheadline.weight(.semibold))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(session.statusDisplay)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    Spacer()
                    Text(formatDate(session.startedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let prompt = session.prompt {
                    Text(prompt)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if let result = session.result, !result.isEmpty {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let err = session.error, !err.isEmpty {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .blue
        case .pendingHITL: return .orange
        case .completed: return .green
        case .failed, .rejected: return .red
        }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso)
        }
        guard let date else { return String(iso.prefix(16)) }
        let display = DateFormatter()
        display.dateFormat = "MM/dd HH:mm"
        return display.string(from: date)
    }
}

// MARK: - Detail Sheet

struct OrchestratorSessionDetailSheet: View {
    let session: OrchestratorSession
    @Environment(\.dismiss) private var dismiss
    @State private var toolCalls: [SessionToolCall] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    markerRow
                    if let prompt = session.prompt {
                        infoCard(title: "명령", icon: "text.bubble", text: prompt)
                    }
                    if let result = session.result, !result.isEmpty {
                        infoCard(title: "결과", icon: "checkmark.seal", text: result)
                    }
                    if let err = session.error, !err.isEmpty {
                        infoCard(title: "에러", icon: "exclamationmark.triangle", text: err, foreground: .red)
                    }
                    if !toolCalls.isEmpty {
                        toolTimelineCard
                    }
                    if let usage = session.usage,
                       let totalTokens = usage.totalTokens, totalTokens > 0 {
                        usageCard(usage)
                    }
                    metaCard
                }
                .padding()
            }
            .navigationTitle("세션 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .task { await loadToolCalls() }
        }
    }

    @MainActor
    private func loadToolCalls() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await OrchestratorAPI.fetchSessionDetail(id: session.id)
            toolCalls = detail.toolCalls
        } catch {
            // silent — 기본 뷰는 여전히 유효
        }
    }

    // MARK: - Marker row (compacted / sub-agent)

    @ViewBuilder
    private var markerRow: some View {
        let hasCompact = toolCalls.contains { $0.isAutoCompact }
        let subAgentCount = toolCalls.filter { $0.isSubAgent }.count
        if hasCompact || subAgentCount > 0 || session.hasSubAgent {
            HStack(spacing: 8) {
                if hasCompact {
                    markerBadge("압축됨", "rectangle.compress.vertical", .yellow)
                }
                if subAgentCount > 0 {
                    markerBadge("sub-agent ×\(subAgentCount)", "shield.lefthalf.filled", .purple)
                }
                Spacer()
            }
        }
    }

    private func markerBadge(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Tool timeline card

    private var toolTimelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("실행 단계 (\(toolCalls.count))", systemImage: "list.bullet")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(toolCalls) { call in
                HStack(spacing: 8) {
                    Image(systemName: toolIcon(call))
                        .font(.caption2)
                        .foregroundStyle(toolColor(call))
                        .frame(width: 14)
                    Text("#\(call.stepIndex ?? 0) \(call.toolName)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                    if call.isSubAgent {
                        Text("sub")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 4)
                            .background(Color.purple.opacity(0.2))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(call.status)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func toolIcon(_ call: SessionToolCall) -> String {
        if call.isAutoCompact { return "rectangle.compress.vertical" }
        if call.isSubAgent { return "shield.lefthalf.filled" }
        if call.status == "ok" { return "checkmark.circle" }
        return "circle"
    }

    private func toolColor(_ call: SessionToolCall) -> Color {
        if call.isAutoCompact { return .yellow }
        if call.isSubAgent { return .purple }
        if call.status == "ok" { return .green }
        return .secondary
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: session.statusIcon)
                .font(.title2)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.agentName.capitalized) · \(session.statusDisplay)")
                    .font(.headline)
                Text(session.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoCard(
        title: String,
        icon: String,
        text: String,
        foreground: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func usageCard(_ usage: SessionUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("LLM 사용량", systemImage: "speedometer")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                if let input = usage.inputTokens {
                    metric(label: "입력", value: "\(input)")
                }
                if let output = usage.outputTokens {
                    metric(label: "출력", value: "\(output)")
                }
                if let total = usage.totalTokens {
                    metric(label: "합계", value: "\(total)")
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("메타", systemImage: "info.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            metaRow("triggered_by", session.triggeredBy)
            metaRow("started_at", session.startedAt)
            if let ended = session.endedAt {
                metaRow("ended_at", ended)
            }
            if let token = session.pendingToken {
                metaRow("pending_token", String(token.prefix(20)) + "…")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .blue
        case .pendingHITL: return .orange
        case .completed: return .green
        case .failed, .rejected: return .red
        }
    }
}
