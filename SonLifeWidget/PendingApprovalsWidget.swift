import SwiftUI
import WidgetKit

/// 홈 화면 / 잠금 화면 위젯 — 승인 대기 건수 + 진행 중 세션.
struct PendingApprovalsWidget: Widget {
    let kind = "PendingApprovalsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PendingApprovalsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("작업 현황")
        .description("승인 대기 및 진행 중인 에이전트 작업을 확인합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Timeline

struct PendingApprovalsEntry: TimelineEntry {
    let date: Date
    let pendingCount: Int
    let runningCount: Int
    let items: [WidgetData.Snapshot.Item]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> PendingApprovalsEntry {
        PendingApprovalsEntry(date: .now, pendingCount: 2, runningCount: 1, items: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (PendingApprovalsEntry) -> Void) {
        completion(entry(from: WidgetData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PendingApprovalsEntry>) -> Void) {
        let current = entry(from: WidgetData.load())
        // 5분 뒤 다시 갱신
        let next = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
        completion(Timeline(entries: [current], policy: .after(next)))
    }

    private func entry(from snapshot: WidgetData.Snapshot?) -> PendingApprovalsEntry {
        PendingApprovalsEntry(
            date: snapshot?.updatedAt ?? .now,
            pendingCount: snapshot?.pendingCount ?? 0,
            runningCount: snapshot?.runningCount ?? 0,
            items: snapshot?.items ?? []
        )
    }
}

// MARK: - Views

struct PendingApprovalsEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: PendingApprovalsEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        default:
            smallView
        }
    }

    // MARK: - Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Spacer()
                if entry.runningCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(.blue)
                            .frame(width: 6, height: 6)
                        Text("\(entry.runningCount)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            Text("\(entry.pendingCount)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(entry.pendingCount > 0 ? .orange : .secondary)

            Text("승인 대기")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(2)
    }

    // MARK: - Medium

    private var mediumView: some View {
        HStack(spacing: 12) {
            // 왼쪽: 카운트
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text("작업 현황")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 16) {
                    countBlock(value: entry.pendingCount, label: "대기", color: .orange)
                    countBlock(value: entry.runningCount, label: "진행", color: .blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 오른쪽: 최근 항목
            if !entry.items.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.items.prefix(3), id: \.token) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Text(item.toolLabel)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(2)
    }

    private func countBlock(value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(value > 0 ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Lock screen (circular)

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: "hourglass")
                    .font(.caption)
                Text("\(entry.pendingCount)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }
            .foregroundStyle(entry.pendingCount > 0 ? .primary : .secondary)
        }
    }

    // MARK: - Lock screen (rectangular)

    private var rectangularView: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass.circle.fill")
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("승인 대기 \(entry.pendingCount)건")
                    .font(.caption.weight(.semibold))
                if entry.runningCount > 0 {
                    Text("진행 중 \(entry.runningCount)건")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
