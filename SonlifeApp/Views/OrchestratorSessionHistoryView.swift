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
                    Text(stripMarkdown(prompt))
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                if let result = session.result, !result.isEmpty {
                    Text(stripMarkdown(result))
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
    @State private var promptExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 상단 상태 배너
                    statusBanner

                    VStack(alignment: .leading, spacing: 14) {
                        // 명령 프롬프트
                        if let prompt = session.prompt, !prompt.isEmpty {
                            promptSection(prompt)
                        }

                        // 받은 메시지 (자율 트리거)
                        if let ctx = session.triggerContext,
                           let content = ctx.originalContent, !content.isEmpty {
                            receivedBubble(ctx: ctx, content: content)
                        }

                        // 결과 (항상 표시)
                        if let result = session.result, !result.isEmpty {
                            resultSection(result)
                        }

                        // 에러
                        if let err = session.error, !err.isEmpty {
                            errorSection(err)
                        }

                        // AI 수행 내용 (primaryContent 있는 tool call)
                        let actionCalls = toolCalls.filter { $0.primaryContent != nil && !$0.isAutoCompact }
                        if !actionCalls.isEmpty {
                            aiActionsSection(actionCalls)
                        }

                        // 실행 단계 (항상 표시)
                        if !toolCalls.isEmpty {
                            stepsSection
                        } else if isLoading {
                            HStack {
                                ProgressView().scaleEffect(0.7)
                                Text("단계 불러오는 중…")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 2)
                        }

                        // 하단 푸터 (사용량 + 메타)
                        footerSection
                    }
                    .padding(16)
                }
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

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: session.statusIcon)
                    .font(.body)
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(session.agentName.capitalized)
                    .font(.subheadline.weight(.semibold))
                Text(session.statusDisplay)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatIso(session.startedAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let ended = session.endedAt {
                    Text(durationString(from: session.startedAt, to: ended))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            markerBadges
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(statusColor.opacity(0.08))
    }

    // MARK: - Prompt Section

    private func promptSection(_ text: String) -> some View {
        let isLong = text.count > 400
        return sectionCard(label: "명령", icon: "text.bubble", accent: .secondary) {
            VStack(alignment: .leading, spacing: 8) {
                if isLong && !promptExpanded {
                    MarkdownText(source: String(text.prefix(400)) + "…")
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownText(source: text)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    if isLong {
                        Button(promptExpanded ? "접기" : "더 보기") {
                            withAnimation(.easeInOut(duration: 0.2)) { promptExpanded.toggle() }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = text
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Received Bubble

    private func receivedBubble(ctx: TriggerContext, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: sourceIcon(ctx.source))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("\(ctx.displaySourceLabel)  \(ctx.displaySender)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                if let ts = ctx.timestamp {
                    Text(formatIso(ts))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(content)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.orange.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Result Section

    private func resultSection(_ result: String) -> some View {
        sectionCard(label: "결과", icon: "checkmark.circle.fill", accent: .green) {
            MarkdownText(source: result)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        sectionCard(label: "에러", icon: "exclamationmark.triangle.fill", accent: .red) {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.red)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - AI Actions Section

    private func aiActionsSection(_ calls: [SessionToolCall]) -> some View {
        sectionCard(label: "AI 수행 내용", icon: "sparkles", accent: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(calls) { call in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: call.status == "ok" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(call.status == "ok" ? .green : .red)
                            Text(call.toolDisplayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let content = call.primaryContent {
                            Text(content)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineSpacing(2)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if call.id != calls.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        sectionCard(label: "실행 단계 (\(toolCalls.count))", icon: "list.number", accent: .secondary) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(toolCalls) { call in
                    HStack(spacing: 8) {
                        Text(call.stepIndex.map { "\($0)" } ?? "-")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.quaternary)
                            .frame(width: 18, alignment: .trailing)

                        Image(systemName: toolIcon(call))
                            .font(.caption2)
                            .foregroundStyle(toolColor(call))
                            .frame(width: 12)

                        Text(call.toolName)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        if call.isSubAgent {
                            Text("sub")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15))
                                .foregroundStyle(.purple)
                                .clipShape(Capsule())
                        }

                        Text(call.status)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let usage = session.usage, let total = usage.totalTokens, total > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let input = usage.inputTokens { tokenChip("in \(input)") }
                    if let output = usage.outputTokens { tokenChip("out \(output)") }
                    tokenChip("total \(total)")
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text(session.triggeredBy)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.quaternary)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(String(session.id.prefix(16)) + "…")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.quaternary)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, 6)
    }

    private func tokenChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Color(.tertiarySystemFill))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
    }

    // MARK: - Section card helper

    private func sectionCard<Content: View>(
        label: String,
        icon: String,
        accent: Color,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Marker badges

    @ViewBuilder
    private var markerBadges: some View {
        let hasCompact = toolCalls.contains { $0.isAutoCompact }
        let subCount = toolCalls.filter { $0.isSubAgent }.count
        if hasCompact || subCount > 0 || session.hasSubAgent {
            HStack(spacing: 4) {
                if hasCompact {
                    badgePill("압축", "rectangle.compress.vertical", .yellow)
                }
                if subCount > 0 || session.hasSubAgent {
                    badgePill("sub×\(max(subCount, 1))", "shield.lefthalf.filled", .purple)
                }
            }
        }
    }

    private func badgePill(_ text: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func sourceIcon(_ source: String?) -> String {
        switch source {
        case "email":     return "envelope.fill"
        case "teams":     return "person.3.fill"
        case "kakaotalk": return "message.fill"
        case "github":    return "chevron.left.forwardslash.chevron.right"
        default:          return "bell.fill"
        }
    }

    private func formatIso(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = fmt.date(from: iso)
        if date == nil {
            fmt.formatOptions = [.withInternetDateTime]
            date = fmt.date(from: iso)
        }
        guard let date else { return String(iso.prefix(16)) }
        let display = DateFormatter()
        display.dateFormat = "MM/dd HH:mm"
        return display.string(from: date)
    }

    private func durationString(from startIso: String, to endIso: String) -> String {
        func parse(_ iso: String) -> Date? {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fmt.date(from: iso) { return d }
            fmt.formatOptions = [.withInternetDateTime]
            return fmt.date(from: iso)
        }
        guard let s = parse(startIso), let e = parse(endIso) else { return "" }
        let secs = Int(e.timeIntervalSince(s))
        guard secs > 0 else { return "" }
        return secs < 60 ? "\(secs)s" : "\(secs / 60)m \(secs % 60)s"
    }

    private func toolIcon(_ call: SessionToolCall) -> String {
        if call.isAutoCompact { return "rectangle.compress.vertical" }
        if call.isSubAgent    { return "shield.lefthalf.filled" }
        if call.status == "ok" { return "checkmark.circle.fill" }
        return "circle"
    }

    private func toolColor(_ call: SessionToolCall) -> Color {
        if call.isAutoCompact { return .yellow }
        if call.isSubAgent    { return .purple }
        if call.status == "ok" { return .green }
        return .secondary
    }

    private var statusColor: Color {
        switch session.status {
        case .running:           return .blue
        case .pendingHITL:       return .orange
        case .completed:         return .green
        case .failed, .rejected: return .red
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
}
