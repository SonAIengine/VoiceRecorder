import AppIntents

// MARK: - D2: Siri Shortcuts (AppIntents)

struct SendCommandIntent: AppIntent {
    static var title: LocalizedStringResource = "에이전트에게 명령"
    static var description = IntentDescription("SonLife 에이전트에게 자연어 명령을 전달합니다")

    @Parameter(title: "명령")
    var command: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let response = try await OrchestratorAPI.dispatch(input: command)
        return .result(dialog: "명령을 전달했습니다: \(response.status.rawValue)")
    }
}

struct CheckPendingIntent: AppIntent {
    static var title: LocalizedStringResource = "승인 대기 확인"
    static var description = IntentDescription("현재 승인 대기 중인 작업 수를 확인합니다")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let approvals = try await OrchestratorAPI.fetchPendingApprovals()
        if approvals.isEmpty {
            return .result(dialog: "승인 대기 중인 작업이 없습니다")
        }
        return .result(dialog: "승인 대기 \(approvals.count)건이 있습니다")
    }
}

struct QuickApproveIntent: AppIntent {
    static var title: LocalizedStringResource = "최근 승인 요청 승인"
    static var description = IntentDescription("가장 최근 승인 요청을 승인합니다")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let approvals = try await OrchestratorAPI.fetchPendingApprovals()
        guard let latest = approvals.first else {
            return .result(dialog: "승인 대기 중인 작업이 없습니다")
        }
        _ = try await OrchestratorAPI.approve(token: latest.token)
        let label = latest.preview.summary ?? latest.toolName
        return .result(dialog: "\(label) 승인 완료")
    }
}

// MARK: - AppShortcutsProvider for Siri suggestions

struct SonlifeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendCommandIntent(),
            phrases: [
                "\(.applicationName) 에이전트에게 명령 ���내",
                "\(.applicationName) 명령 전달",
            ],
            shortTitle: "에이전트 명령",
            systemImageName: "text.bubble"
        )

        AppShortcut(
            intent: CheckPendingIntent(),
            phrases: [
                "\(.applicationName) 승인 대기 확인해줘",
                "\(.applicationName) 에이전�� 작업 있어?",
            ],
            shortTitle: "대기 확인",
            systemImageName: "hourglass"
        )
    }
}
