import SwiftUI

/// M1a #7 — 품질 지표 대시보드.
///
/// /api/metrics/rejection_rate 를 조회해서 "AI 가 나처럼 답하고 있는가" 의
/// 1차 지표를 한 화면에. M1b 시작 전의 baseline 역할.
///
/// 표시:
/// - 주간 거절률 (대형 숫자 + 색)
/// - 총 결정 수, 승인/거절/수정 분해
/// - 수정률 (승인 중 편집 비율)
/// - Source 별 breakdown (teams/email/kakao 등)
/// - Origin 별 breakdown (autonomous/user)
///
/// 기간 선택: 7일 / 14일 / 30일 segmented picker.
struct QualityMetricsView: View {
    @State private var metrics: RejectionMetrics?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedDays: Int = 7

    private let dayOptions = [7, 14, 30]

    var body: some View {
        Group {
            if isLoading && metrics == nil {
                ProgressView("로딩 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage, metrics == nil {
                ContentUnavailableView(
                    "품질 지표 로드 실패",
                    systemImage: "exclamationmark.triangle",
                    description: Text(err)
                )
            } else if let metrics {
                content(metrics)
            } else {
                ContentUnavailableView(
                    "데이터 없음",
                    systemImage: "tray",
                    description: Text("지표를 불러올 수 없습니다")
                )
            }
        }
        .navigationTitle("품질 지표")
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
    private func content(_ m: RejectionMetrics) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                dayPickerCard

                headlineCard(m)
                distributionCard(m)

                if !m.bySource.isEmpty {
                    breakdownCard(title: "소스별", icon: "tray.and.arrow.down", items: m.bySource)
                }
                if !m.byOrigin.isEmpty {
                    breakdownCard(title: "세션 기원별", icon: "person.crop.circle", items: m.byOrigin)
                }

                baselineNoteCard
            }
            .padding()
        }
    }

    // MARK: - Day picker

    private var dayPickerCard: some View {
        Picker("기간", selection: $selectedDays) {
            ForEach(dayOptions, id: \.self) { d in
                Text("\(d)일").tag(d)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedDays) {
            Task { await load() }
        }
    }

    // MARK: - Headline card

    private func headlineCard(_ m: RejectionMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(rateColor(m.rejectionRate))
                Text("주간 거절률")
                    .font(.headline)
                Spacer()
            }

            if let rate = m.rejectionRate {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(rate * 100))%")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(rateColor(rate))
                    Text("거절됨")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("데이터 없음")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("\(m.window.days)일 윈도우 · 총 \(m.totalResolved)건 결정")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let editRate = m.editRate {
                HStack {
                    Image(systemName: "pencil.tip")
                        .foregroundStyle(.blue)
                    Text("수정률 \(Int(editRate * 100))%")
                        .font(.caption)
                    Text("— 승인 중 편집 후 발송 비율")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func rateColor(_ rate: Double?) -> Color {
        guard let rate else { return .gray }
        if rate >= 0.5 { return .red }
        if rate >= 0.3 { return .orange }
        if rate >= 0.15 { return .yellow }
        return .green
    }

    // MARK: - Distribution card

    private func distributionCard(_ m: RejectionMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.purple)
                Text("결정 분포")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 16) {
                distMetric(label: "승인", value: m.approved, color: .green)
                distMetric(label: "거절", value: m.rejected, color: .red)
                distMetric(label: "수정", value: m.modified, color: .blue)
                distMetric(label: "대기", value: m.pendingInWindow, color: .orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func distMetric(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Breakdown card

    private func breakdownCard(
        title: String,
        icon: String,
        items: [String: MetricsBreakdown]
    ) -> some View {
        let sorted = items.sorted { $0.value.total > $1.value.total }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.teal)
                Text(title)
                    .font(.headline)
                Spacer()
            }

            ForEach(sorted, id: \.key) { entry in
                breakdownRow(name: entry.key, b: entry.value)
                if entry.key != sorted.last?.key {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func breakdownRow(name: String, b: MetricsBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(labelFor(name))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let rate = b.rejectionRate {
                    Text("\(Int(rate * 100))% 거절")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(rateColor(rate))
                }
            }
            HStack(spacing: 4) {
                Text("총 \(b.total)")
                    .font(.caption)
                Text("·")
                Text("승인 \(b.approved)")
                    .foregroundStyle(.green)
                    .font(.caption.monospacedDigit())
                Text("·")
                Text("거절 \(b.rejected)")
                    .foregroundStyle(.red)
                    .font(.caption.monospacedDigit())
                if b.modified > 0 {
                    Text("·")
                    Text("수정 \(b.modified)")
                        .foregroundStyle(.blue)
                        .font(.caption.monospacedDigit())
                }
                Spacer()
            }
            .foregroundStyle(.secondary)

            if b.resolved > 0, let rate = b.rejectionRate {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.green.opacity(0.3))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(rateColor(rate))
                            .frame(width: max(4, geo.size.width * rate))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 4)
    }

    private func labelFor(_ key: String) -> String {
        switch key {
        case "teams": return "Teams"
        case "email": return "이메일"
        case "kakaotalk": return "카카오톡"
        case "calendar": return "캘린더"
        case "github": return "GitHub"
        case "gitlab": return "GitLab"
        case "autonomous": return "자율 세션"
        case "user": return "사용자 명령"
        case "unknown": return "미분류"
        default: return key
        }
    }

    // MARK: - Baseline note

    private var baselineNoteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("M1b baseline", systemImage: "flag.checkered")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("이 거절률이 M1b 정체성 시딩 이후 어떻게 변하는지가 품질 개선의 증거입니다. 목표: 0.3 이하.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Load

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            metrics = try await HarnessService.fetchRejectionMetrics(days: selectedDays)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
