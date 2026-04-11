import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "시스템"
    case light = "라이트"
    case dark = "다크"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @State private var serverURL: String = ChunkUploader.shared.currentServerURL
    @State private var testStatus: TestStatus = .idle
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue
    @AppStorage("stt_vocabulary") private var vocabulary: String = ""
    @AppStorage("llm_provider") private var llmProvider: String = "off"
    @AppStorage("ollama_model") private var ollamaModel: String = ""
    @State private var availableModels: [OllamaModel] = []
    @State private var isLoadingModels = false
    @State private var autonomyState: AutonomyState?
    @State private var autonomyError: String?
    @State private var isUpdatingAutonomy = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            autonomySection

            Section("화면 모드") {
                Picker("테마", selection: $selectedTheme) {
                    ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                        Text(theme.rawValue).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField("자주 사용하는 용어를 입력하세요", text: $vocabulary, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("커스텀 용어")
            } footer: {
                Text("STT 인식률을 높이기 위한 힌트 (예: 데이터 마이닝, 레벤슈타인, RNN)")
            }

            Section {
                Picker("AI 요약", selection: $llmProvider) {
                    Text("사용 안 함").tag("off")
                    Text("Claude (Haiku)").tag("claude")
                    Text("Ollama (로컬)").tag("ollama")
                }
                .onChange(of: llmProvider) { _, newValue in
                    if newValue == "ollama" {
                        loadOllamaModels()
                    }
                }

                if llmProvider == "ollama" {
                    if isLoadingModels {
                        HStack {
                            Text("모델 로딩 중...")
                            Spacer()
                            ProgressView()
                        }
                    } else if !availableModels.isEmpty {
                        Picker("Ollama 모델", selection: $ollamaModel) {
                            ForEach(availableModels, id: \.name) { model in
                                Text("\(model.name) (\(model.sizeText))").tag(model.name)
                            }
                        }
                    } else {
                        Button("모델 목록 새로고침") {
                            loadOllamaModels()
                        }
                    }
                }
            } header: {
                Text("AI 요약")
            } footer: {
                switch llmProvider {
                case "claude": Text("Anthropic API 키 필요 (서버 .env에 설정)")
                case "ollama": Text("Home 서버의 Ollama 모델로 요약")
                default: Text("세션 종료 시 Obsidian에 AI 요약이 추가됩니다")
                }
            }

            Section("STT 서버") {
                TextField("서버 URL", text: $serverURL)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("연결 테스트")
                        Spacer()
                        switch testStatus {
                        case .idle:
                            EmptyView()
                        case .testing:
                            ProgressView()
                        case .success(let info):
                            Text(info)
                                .font(.caption)
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .disabled(testStatus == .testing)
            }

            Section {
                Button("저장") {
                    ChunkUploader.shared.currentServerURL = serverURL
                    dismiss()
                }
                .disabled(serverURL.isEmpty)
            }

            #if DEBUG
            Section {
                Button {
                    showDevFeedback = true
                } label: {
                    Label("피드백 UI 테스트", systemImage: "ladybug")
                }
            } header: {
                Text("개발자")
            } footer: {
                Text("가짜 session_id로 FeedbackView를 띄워 서버 /api/feedback 동작 확인")
            }
            #endif
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAutonomyState() }
        #if DEBUG
        .sheet(isPresented: $showDevFeedback) {
            FeedbackView(
                sessionId: "dev-test-\(Int(Date().timeIntervalSince1970))",
                summaryPreview: "오늘은 H3-A APNs 통합 작업을 진행했다. iOS 앱에 AppDelegate, FeedbackService, FeedbackView를 추가하고 서버 배포를 검증했다."
            )
        }
        #endif
    }

    #if DEBUG
    @State private var showDevFeedback = false
    #endif

    // MARK: - Autonomy section (M1a #2)

    private var autonomySection: some View {
        Section {
            if let state = autonomyState {
                Toggle(isOn: Binding(
                    get: { state.enabled },
                    set: { newValue in
                        Task { await toggleAutonomy(newValue) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("자율 루프 활성")
                            .font(.body)
                        Text(statusSubtitle(for: state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isUpdatingAutonomy)

                if state.hardStopped {
                    Label {
                        Text("예산 150% 초과로 자동 정지됨. 켜면 함께 해제됩니다.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                }

                HStack {
                    Text("처리된 이벤트")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.dispatchedCount) / 관측 \(state.seenCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if let reasons = state.skippedReasons, !reasons.isEmpty {
                    let total = reasons.values.reduce(0, +)
                    HStack {
                        Text("건너뜀")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(total) (\(reasons.keys.sorted().joined(separator: ", ")))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let error = autonomyError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("다시 시도") {
                    Task { await loadAutonomyState() }
                }
            } else {
                HStack {
                    ProgressView()
                    Text("상태 불러오는 중...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("자율 루프")
        } footer: {
            Text("수집기에서 새 메시지가 들어오면 에이전트가 자동으로 답변 초안을 작성합니다. 실제 발송은 승인 후에만 이뤄집니다.")
        }
    }

    private func statusSubtitle(for state: AutonomyState) -> String {
        if state.hardStopped {
            return "예산 초과로 정지 중"
        }
        if state.enabled {
            let ruleText = "룰 \(state.ruleCount)개 활성"
            return state.canDispatch ? ruleText : "\(ruleText) · dispatch 불가"
        }
        if let override = state.overrideEnabled, override == false {
            return "수동 정지됨"
        }
        return "환경변수로 비활성 (AUTONOMY_ENABLED=false)"
    }

    private func loadAutonomyState() async {
        do {
            let state = try await HarnessService.fetchAutonomyState()
            await MainActor.run {
                self.autonomyState = state
                self.autonomyError = nil
            }
        } catch {
            await MainActor.run {
                self.autonomyError = "자율 루프 상태 조회 실패"
            }
        }
    }

    private func toggleAutonomy(_ enable: Bool) async {
        await MainActor.run { self.isUpdatingAutonomy = true }
        defer {
            Task { @MainActor in self.isUpdatingAutonomy = false }
        }
        do {
            // 명시적으로 true/false 를 override 에 기록.
            // nil(환경변수 복귀)은 현재 UI 에서 노출하지 않음 — 항상 의도적 on/off.
            let state = try await HarnessService.setAutonomyEnabled(enable)
            await MainActor.run {
                self.autonomyState = state
                self.autonomyError = nil
                Haptic.tap(.medium)
            }
        } catch {
            await MainActor.run {
                self.autonomyError = "토글 실패 — 네트워크 확인"
            }
        }
    }

    private func testConnection() {
        testStatus = .testing
        guard let url = URL(string: serverURL)?.appendingPathComponent("api/health") else {
            testStatus = .failure("잘못된 URL")
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    testStatus = .failure(error.localizedDescription)
                    return
                }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    testStatus = .failure("서버 응답 오류")
                    return
                }
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String, status == "ok" {
                    let whisper = (json["whisper"] as? [String: Any])?["model"] as? String ?? "?"
                    testStatus = .success(whisper)
                } else {
                    testStatus = .failure("응답 파싱 실패")
                }
            }
        }.resume()
    }

    private func loadOllamaModels() {
        isLoadingModels = true
        guard let url = URL(string: serverURL)?.appendingPathComponent("api/llm/models") else {
            isLoadingModels = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            DispatchQueue.main.async {
                isLoadingModels = false
                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = json["models"] as? [[String: Any]] else {
                    return
                }
                availableModels = models.compactMap { dict in
                    guard let name = dict["name"] as? String else { return nil }
                    let size = dict["size"] as? Int64 ?? 0
                    return OllamaModel(name: name, size: size)
                }
                if ollamaModel.isEmpty, let first = availableModels.first {
                    ollamaModel = first.name
                }
            }
        }.resume()
    }

    private enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }
}

struct OllamaModel {
    let name: String
    let size: Int64

    var sizeText: String {
        let gb = Double(size) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1fGB", gb)
        }
        return String(format: "%.0fMB", Double(size) / 1_048_576)
    }
}
