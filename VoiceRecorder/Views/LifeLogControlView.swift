import SwiftUI

struct LifeLogControlView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 16) {
            // LifeLog 토글
            VStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { recorder.isLifeLogActive },
                    set: { newValue in
                        if newValue {
                            recorder.startLifeLog()
                        } else {
                            recorder.stopLifeLog()
                        }
                    }
                )) {
                    HStack {
                        Image(systemName: recorder.isLifeLogActive ? "waveform.circle.fill" : "waveform.circle")
                            .font(.title2)
                            .foregroundStyle(recorder.isLifeLogActive ? .red : .secondary)
                            .symbolEffect(.pulse, isActive: recorder.isLifeLogActive)
                        Text("LifeLog")
                            .font(.title2.bold())
                    }
                }
                .toggleStyle(.switch)
                .tint(.red)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.1)))

            if recorder.isLifeLogActive {
                // 세션 정보
                VStack(spacing: 12) {
                    HStack {
                        StatView(
                            title: "녹음 시간",
                            value: formatDuration(recorder.lifeLogSessionTime),
                            icon: "clock"
                        )
                        Spacer()
                        StatView(
                            title: "청크",
                            value: "\(recorder.sessionManager.activeSession?.chunkCount ?? 0)개",
                            icon: "square.stack.3d.up"
                        )
                        Spacer()
                        StatView(
                            title: "잔여 저장",
                            value: formatRemainingHours(recorder.sessionManager.estimatedRemainingHours()),
                            icon: "internaldrive"
                        )
                    }

                    // 레벨 미터
                    VStack(alignment: .leading, spacing: 4) {
                        Text("입력 레벨")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AudioLevelMeterView(level: recorder.currentPowerLevel)
                    }

                    // VAD 상태
                    HStack {
                        Circle()
                            .fill(vadColor)
                            .frame(width: 10, height: 10)
                        Text(vadStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(.gray.opacity(0.1)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.3), value: recorder.isLifeLogActive)
    }

    private var vadColor: Color {
        switch recorder.vadState {
        case .active: return .green
        case .silenceDetected: return .yellow
        case .silencePaused: return .gray
        }
    }

    private var vadStatusText: String {
        switch recorder.vadState {
        case .active: return "녹음 중"
        case .silenceDetected:
            let remaining = max(0, 30 - Int(recorder.vadSilenceDuration))
            return "무음 감지 (\(remaining)초 후 자동 일시정지)"
        case .silencePaused:
            return "무음 일시정지 (소리 감지 시 자동 재개)"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func formatRemainingHours(_ hours: Double) -> String {
        if hours > 100 {
            return "\(Int(hours))h"
        }
        return String(format: "%.1fh", hours)
    }
}

struct StatView: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
