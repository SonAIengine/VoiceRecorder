import SwiftUI

struct AgentSessionDetailView: View {
    let sessionId: String

    @State private var detail: AgentSessionDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var expandedIds: Set<String> = []

    var body: some View {
        Group {
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sessionHeader(detail)
                        primarySection(detail.timeline)
                    }
                    .padding()
                }
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "로드 실패",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("로딩 중...")
            }
        }
        .navigationTitle("세션 상세")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadDetail() }
    }

    // MARK: - Header

    private func sessionHeader(_ detail: AgentSessionDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.title)
                .font(.headline)

            if !detail.description.isEmpty {
                Text(detail.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(detail.createdDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                      systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)

                if detail.successCount > 0 {
                    Label("\(detail.successCount)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if detail.failureCount > 0 {
                    Label("\(detail.failureCount)", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Primary section (메시지 + 작업)

    private func primarySection(_ events: [TimelineEvent]) -> some View {
        let messages = events.filter { $0.kind == "observation" || $0.kind == "session" }
        let actions  = events.filter { $0.kind == "tool_call" }
        let others   = events.filter { $0.kind != "observation" && $0.kind != "session" && $0.kind != "tool_call" }

        return VStack(alignment: .leading, spacing: 12) {
            if !messages.isEmpty {
                sectionBlock(title: "받은 메시지", icon: "tray.and.arrow.down.fill", color: .orange, events: messages)
            }
            if !actions.isEmpty {
                sectionBlock(title: "수행한 작업", icon: "wrench.and.screwdriver.fill", color: .blue, events: actions)
            }
            if !others.isEmpty {
                sectionBlock(title: "기타", icon: "ellipsis.circle", color: .secondary, events: others)
            }
            if events.isEmpty {
                Text("이벤트 없음")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Section block

    private func sectionBlock(title: String, icon: String, color: Color, events: [TimelineEvent]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("(\(events.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(events) { event in
                    eventRow(event)
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Event row (접기/펼치기)

    private func eventRow(_ event: TimelineEvent) -> some View {
        let isExpanded = expandedIds.contains(event.id)
        let hasContent = !event.content.isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasContent {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedIds.remove(event.id)
                        } else {
                            expandedIds.insert(event.id)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: event.kindIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(event.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(isExpanded ? nil : 2)

                    Spacer(minLength: 4)

                    Text(event.createdDate.formatted(.dateTime.hour().minute().second()))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    if hasContent {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && hasContent {
                Text(event.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
                .padding(.leading, 40)
        }
    }

    // MARK: - Load

    private func loadDetail() async {
        isLoading = true
        do {
            detail = try await HarnessService.fetchSessionDetail(id: sessionId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
