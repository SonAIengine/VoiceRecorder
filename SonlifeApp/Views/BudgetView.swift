import SwiftUI

/// C-5 Budget 8차원 뷰 — 오늘의 에이전트 사용량/한도 표시.
///
/// `/api/budget`에서 받은 `agents` 목록을 렌더링하고,
/// 각 에이전트의 8차원 (input/output/total/reasoning tokens, cost, runs,
/// tool_calls, delegated_tasks)을 카드로 표시.
struct BudgetView: View {
    @State private var summary: BudgetSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && summary == nil {
                ProgressView("로딩 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage, summary == nil {
                ContentUnavailableView(
                    "예산 로드 실패",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if let summary {
                content(summary)
            } else {
                ContentUnavailableView(
                    "사용 기록 없음",
                    systemImage: "chart.bar",
                    description: Text("오늘 실행된 에이전트가 없습니다")
                )
            }
        }
        .navigationTitle("예산")
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

    private func content(_ summary: BudgetSummary) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                globalCard(summary)

                if summary.agents.isEmpty {
                    Text("오늘 실행된 에이전트가 없습니다")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(summary.agents) { agent in
                        agentCard(agent)
                    }
                }
            }
            .padding()
        }
    }

    private func globalCard(_ summary: BudgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.blue)
                Text("글로벌")
                    .font(.headline)
                Spacer()
                Text(String(format: "$%.4f", summary.globalCostUsd))
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(.blue)
            }
            Text("오늘 전체 에이전트 누적 비용")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func agentCard(_ agent: AgentBudgetUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconFor(agent.agentName))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(agent.agentName.capitalized)
                    .font(.headline)
                Spacer()
                Text(String(format: "$%.4f", agent.costUsd))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.primary)
            }

            // 8 dimensions grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metric("입력 토큰", "\(agent.inputTokens)", icon: "arrow.down.circle")
                metric("출력 토큰", "\(agent.outputTokens)", icon: "arrow.up.circle")
                metric("전체 토큰", "\(agent.totalTokens)", icon: "sum")
                metric("추론 토큰", "\(agent.reasoningTokens)", icon: "brain")
                metric("세션 수", "\(agent.runs)", icon: "play.circle")
                metric("도구 호출", "\(agent.toolCalls)", icon: "hammer")
                metric("위임 작업", "\(agent.delegatedTasks)", icon: "person.2")
                metric("비용", String(format: "$%.4f", agent.costUsd), icon: "dollarsign.circle")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metric(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            Spacer()
        }
        .padding(6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func iconFor(_ agentName: String) -> String {
        switch agentName {
        case "email": return "envelope"
        case "coding": return "chevron.left.forwardslash.chevron.right"
        case "research": return "magnifyingglass"
        default: return "person.circle"
        }
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            summary = try await OrchestratorAPI.fetchBudget()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
