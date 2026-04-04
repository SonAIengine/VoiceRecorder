import SwiftUI

enum AppMode: String, CaseIterable {
    case lifeLog = "LifeLog"
    case manual = "녹음"
}

struct ContentView: View {
    @State private var recorder = AudioRecorder()
    @State private var mode: AppMode = .lifeLog

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(AppMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                switch mode {
                case .lifeLog:
                    LifeLogView(recorder: recorder)
                case .manual:
                    ManualRecordingView(recorder: recorder)
                }
            }
            .navigationTitle("VoiceRecorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .alert("오류", isPresented: .init(
                get: { recorder.errorMessage != nil },
                set: { if !$0 { recorder.errorMessage = nil } }
            )) {
                Button("확인") { recorder.errorMessage = nil }
            } message: {
                Text(recorder.errorMessage ?? "")
            }
        }
    }
}

// MARK: - LifeLog Tab

struct LifeLogView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 0) {
            LifeLogControlView(recorder: recorder)
                .padding(.top, 8)

            SessionListView(sessionManager: recorder.sessionManager)
        }
    }
}

// MARK: - Manual Recording Tab (기존 UI 유지)

struct ManualRecordingView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(recorder.recordings) { recording in
                    NavigationLink {
                        RecordingDetailView(recording: recording, recorder: recorder)
                    } label: {
                        RecordingRow(recording: recording)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        recorder.deleteRecording(recorder.recordings[index])
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if recorder.recordings.isEmpty {
                    ContentUnavailableView(
                        "녹음이 없습니다",
                        systemImage: "mic.slash",
                        description: Text("아래 버튼을 눌러 녹음을 시작하세요")
                    )
                }
            }

            Divider()

            RecordingControlView(recorder: recorder)
                .padding()
                .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Shared Components

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.date.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)

            if let transcript = recording.transcript {
                Text(transcript)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("STT 변환 중...")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

struct RecordingControlView: View {
    @Bindable var recorder: AudioRecorder

    var body: some View {
        VStack(spacing: 12) {
            if recorder.isRecording {
                Text(formatTime(recorder.currentTime))
                    .font(.system(.title, design: .monospaced))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 40) {
                if recorder.isRecording {
                    Button {
                        if recorder.isPaused {
                            recorder.resumeRecording()
                        } else {
                            recorder.pauseRecording()
                        }
                    } label: {
                        Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.title)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(.gray.opacity(0.2)))
                    }

                    Button {
                        recorder.stopRecording()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 60, height: 60)
                            .background(Circle().fill(.red))
                    }
                } else {
                    Button {
                        recorder.startRecording()
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 70, height: 70)
                            .background(Circle().fill(.red))
                    }
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let tenths = Int((time - Double(Int(time))) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
