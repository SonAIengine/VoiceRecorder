import SwiftUI

/// Phase D 메모리 관측 대시보드.
///
/// synaptic 그래프 상태 + D-3a SynapticIngestor 의 health/카운터를 한 화면에.
/// backfill 을 돌리기 전/후 또는 자율 루프 운영 중 "그래프가 건강한가, 뭐가
/// 쌓이고 있는가" 를 사용자가 눈으로 확인하기 위한 자리.
struct MemoryStatsView: View {
    @State private var stats: MemoryStatsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && stats == nil {
                ProgressView("로딩 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage, stats == nil {
                ContentUnavailableView(
                    "메모리 상태 로드 실패",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if let stats {
                content(stats)
            } else {
                ContentUnavailableView(
                    "데이터 없음",
                    systemImage: "tray",
                    description: Text("메모리 상태를 불러올 수 없습니다")
                )
            }
        }
        .navigationTitle("메모리")
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
    private func content(_ resp: MemoryStatsResponse) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ingestorCard(resp.ingestor)
                graphSummaryCard(resp.graph)
                if !resp.graph.kindCounts.isEmpty {
                    kindBreakdownCard(resp.graph.kindCounts)
                }
                if !resp.graph.levelCounts.isEmpty {
                    levelBreakdownCard(resp.graph.levelCounts)
                }
                if let err = resp.graph.error {
                    errorCard(err)
                }
            }
            .padding()
        }
    }

    // MARK: - Cards

    private func ingestorCard(_ ing: IngestorStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: ing.healthy ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ing.healthy ? .green : .red)
                Text(ing.healthy ? "Ingestor 정상" : "Ingestor 비정상")
                    .font(.headline)
                Spacer()
            }

            if let last = ing.lastError, !last.isEmpty {
                Text(last)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 16) {
                metric(label: "누적 상태", value: "\(ing.stateCount)")
                metric(label: "이번 세션", value: "\(ing.ingestedCount)")
                metric(label: "중복 skip", value: "\(ing.skippedDuplicates)")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func graphSummaryCard(_ graph: MemoryGraphStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.indigo)
                Text("synaptic 그래프")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                metric(label: "전체 노드", value: "\(graph.totalNodes)", big: true)
                metric(label: "캐시 사이즈", value: "\(graph.cacheSize)")
                metric(
                    label: "캐시 히트율",
                    value: String(format: "%.0f%%", graph.cacheHitRate * 100)
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func kindBreakdownCard(_ kinds: [String: Int]) -> some View {
        let sorted = kinds.sorted { $0.value > $1.value }
        let total = max(sorted.reduce(0) { $0 + $1.value }, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("소스/유형별")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(sorted, id: \.key) { item in
                kindRow(
                    name: item.key,
                    count: item.value,
                    ratio: Double(item.value) / Double(total)
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func levelBreakdownCard(_ levels: [String: Int]) -> some View {
        let order = ["L0", "L1", "L2", "L3"]
        let rows = order.compactMap { key -> (String, Int)? in
            guard let v = levels[key] else { return nil }
            return (key, v)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Consolidation Tier")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(rows, id: \.0) { row in
                    VStack(spacing: 4) {
                        Text(row.0)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text("\(row.1)")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(tierColor(row.0))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(tierColor(row.0).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("graph.stats() 오류", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)
            Text(msg)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bits

    private func metric(label: String, value: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(big ? .title2.monospacedDigit() : .subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kindRow(name: String, count: Int, ratio: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.indigo.opacity(0.6))
                    .frame(width: max(4, geo.size.width * ratio), height: 6)
            }
            .frame(height: 6)
        }
    }

    private func tierColor(_ level: String) -> Color {
        switch level {
        case "L0": return .blue
        case "L1": return .teal
        case "L2": return .green
        case "L3": return .purple
        default: return .gray
        }
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            stats = try await OrchestratorAPI.fetchMemoryStats()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
