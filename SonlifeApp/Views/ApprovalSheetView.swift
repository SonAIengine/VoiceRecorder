import SwiftUI

/// Phase D 자율 루프 HITL 승인 시트.
///
/// 자율 에이전트(또는 사용자 명령) 가 외부 부작용 도구(send_email,
/// send_teams_message, commit_and_push 등) 를 호출하면 L03 permission
/// hook 이 suspend 시키고 APNs 로 알림을 보낸다. 사용자는 이 시트에서
/// 원본 → 답장 쌍을 보고 발송/거절/수정을 결정한다.
///
/// 설계 원칙 (UI/UX 2026-04-11):
/// - 기술 용어(tool_name, chat_id, permission level) 는 "기술 상세" 로 접음
/// - 원본 메시지(trigger_context) 와 보낼 답장(args) 을 쌍으로 표시
/// - 액션 버튼은 결과 언어("발송하기") — "승인" 은 모호함
/// - 사용자 명령 세션엔 trigger_context 없음 → source card 없이 draft 만
struct ApprovalSheetView: View {
    let approval: ApprovalDetail
    let onResolved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editedTo: String
    @State private var editedSubject: String
    @State private var editedBody: String
    @State private var editedChatId: String
    @State private var isEditing = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var showTechnicalDetails = false

    init(approval: ApprovalDetail, onResolved: @escaping () -> Void) {
        self.approval = approval
        self.onResolved = onResolved
        _editedTo = State(initialValue: approval.args.to ?? "")
        _editedSubject = State(initialValue: approval.args.subject ?? "")
        _editedBody = State(initialValue: approval.args.body ?? "")
        _editedChatId = State(initialValue: approval.args.chatId ?? "")
    }

    // MARK: - Derived properties

    private var toolKind: ToolKind {
        switch approval.toolName {
        case "send_email": return .email
        case "send_teams_message": return .teams
        case "commit_and_push": return .commit
        default: return .other
        }
    }

    private var hasTrigger: Bool {
        approval.triggerContext != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroHeader

                    if let trigger = approval.triggerContext {
                        sourceCard(trigger)
                    }

                    draftCard

                    actionDescriptionLine

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    if let result = resultMessage {
                        Label(result, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    technicalDetailsDisclosure
                }
                .padding()
            }
            .navigationTitle("승인 요청")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "취소" : "수정") {
                        if isEditing {
                            editedTo = approval.args.to ?? ""
                            editedSubject = approval.args.subject ?? ""
                            editedBody = approval.args.body ?? ""
                            editedChatId = approval.args.chatId ?? ""
                        }
                        isEditing.toggle()
                    }
                    .disabled(isSubmitting || resultMessage != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
            }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: heroIcon)
                    .font(.title)
                    .foregroundStyle(heroColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(heroTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(heroSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var heroIcon: String {
        if hasTrigger {
            switch toolKind {
            case .email: return "envelope.badge"
            case .teams: return "bubble.left.and.bubble.right.fill"
            case .commit: return "arrow.up.doc.fill"
            case .other: return "sparkles"
            }
        }
        return "person.crop.circle.badge.questionmark"
    }

    private var heroColor: Color {
        switch toolKind {
        case .teams: return .indigo
        case .email: return .blue
        case .commit: return .orange
        case .other: return .purple
        }
    }

    private var heroTitle: String {
        if let trigger = approval.triggerContext {
            let sender = trigger.displaySender
            let target = trigger.displaySourceLabel
            return "\(sender)에게 \(target) 답장 준비했어요"
        }
        switch toolKind {
        case .email: return "이메일 발송 승인"
        case .teams: return "Teams 메시지 발송 승인"
        case .commit: return "Git push 승인"
        case .other: return "외부 액션 승인"
        }
    }

    private var heroSubtitle: String {
        var parts: [String] = []
        if let trigger = approval.triggerContext {
            parts.append(relativeTimeString(trigger.timestamp) ?? "방금")
            parts.append(trigger.displaySourceLabel)
            if let channel = trigger.channel, !channel.isEmpty, channel != "oneOnOne" {
                parts.append(channel)
            } else if trigger.channel == "oneOnOne" {
                parts.append("1:1 DM")
            }
        } else {
            parts.append("사용자 명령")
            parts.append(approval.toolName)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Source card (받은 메시지)

    private func sourceCard(_ trigger: TriggerContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.open")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("받은 메시지")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let importance = trigger.importance, importance == "high" {
                    Text("높은 중요도")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            if let title = trigger.originalTitle,
               !title.isEmpty,
               trigger.source == "email" {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            Text((trigger.originalContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Draft card (보낼 답장)

    private var draftCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(heroColor)
                Text("보낼 답장")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(heroColor)
                Spacer()
                if isEditing {
                    Text("편집 중")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            switch toolKind {
            case .email:
                emailEditor
            case .teams:
                teamsEditor
            case .commit, .other:
                rawEditor
            }

            if !isEditing {
                Text("탭해서 수정")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(heroColor.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(heroColor.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing, !isSubmitting, resultMessage == nil {
                isEditing = true
            }
        }
    }

    // MARK: - Per-tool editors

    private var emailEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeledField("받는 사람") {
                if isEditing {
                    TextField("To", text: $editedTo)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(editedTo.isEmpty ? "-" : editedTo)
                        .font(.body)
                }
            }
            labeledField("제목") {
                if isEditing {
                    TextField("Subject", text: $editedSubject)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(editedSubject.isEmpty ? "-" : editedSubject)
                        .font(.body.weight(.medium))
                }
            }
            labeledField("본문") {
                if isEditing {
                    TextEditor(text: $editedBody)
                        .frame(minHeight: 200)
                        .padding(6)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if editedBody.isEmpty {
                    Text("-")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownText(source: editedBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var teamsEditor: some View {
        Group {
            if isEditing {
                TextEditor(text: $editedBody)
                    .frame(minHeight: 150)
                    .padding(6)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if editedBody.isEmpty {
                Text("-")
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownText(source: editedBody)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let to = approval.args.to { Text("to: \(to)").font(.caption.monospaced()) }
            if let subject = approval.args.subject {
                Text("subject: \(subject)").font(.caption.monospaced())
            }
            if let chatId = approval.args.chatId {
                Text("chat_id: \(chatId)").font(.caption.monospaced()).lineLimit(1)
            }
            if let body = approval.args.body {
                Text(body).font(.footnote).padding(.top, 4)
            }
        }
    }

    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Action description

    private var actionDescriptionLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(actionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var actionDescription: String {
        switch toolKind {
        case .email:
            let to = approval.args.to ?? ""
            return "승인하면 \(to.isEmpty ? "수신자에게" : to + "에게") 메일이 실제로 발송됩니다"
        case .teams:
            if let trigger = approval.triggerContext, let sender = trigger.sender {
                return "승인하면 \(sender)에게 Teams 채팅으로 실제로 발송됩니다"
            }
            return "승인하면 Teams 채팅방에 실제로 메시지가 전송됩니다"
        case .commit:
            return "승인하면 remote repository 로 commit + push 가 실행됩니다"
        case .other:
            return "승인하면 외부 액션이 실제로 수행됩니다 (되돌릴 수 없음)"
        }
    }

    // MARK: - Technical details disclosure

    private var technicalDetailsDisclosure: some View {
        DisclosureGroup(isExpanded: $showTechnicalDetails) {
            VStack(alignment: .leading, spacing: 6) {
                detailRow("tool", approval.toolName)
                detailRow("permission", approval.preview.permission ?? "-")
                detailRow("session_id", approval.sessionId)
                detailRow("token", approval.token)
                if let chatId = approval.args.chatId {
                    detailRow("chat_id", chatId)
                }
                if let agent = approval.preview.agent {
                    detailRow("agent", agent)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("기술 상세")
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) {
                Task { await reject() }
            } label: {
                Label("거절", systemImage: "xmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isSubmitting || resultMessage != nil)

            Button {
                Task { await approve() }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Label(primaryActionLabel, systemImage: "paperplane.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSubmitting || resultMessage != nil)
        }
        .padding()
        .background(.bar)
    }

    private var primaryActionLabel: String {
        switch toolKind {
        case .email: return hasEdits ? "수정해서 발송" : "발송하기"
        case .teams: return hasEdits ? "수정해서 발송" : "발송하기"
        case .commit: return "push 실행"
        case .other: return "승인"
        }
    }

    private var hasEdits: Bool {
        editedTo != (approval.args.to ?? "")
            || editedSubject != (approval.args.subject ?? "")
            || editedBody != (approval.args.body ?? "")
    }

    // MARK: - Actions

    @MainActor
    private func approve() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let modified: ApprovalArgs? = hasEdits
                ? ApprovalArgs(
                    to: toolKind == .email ? editedTo : nil,
                    subject: toolKind == .email ? editedSubject : nil,
                    body: editedBody,
                    chatId: toolKind == .teams ? approval.args.chatId : nil
                )
                : nil
            let response = try await OrchestratorAPI.approve(
                token: approval.token,
                modifiedArgs: modified
            )
            Haptic.success()
            resultMessage = response.result?.summary ?? "처리 완료"
            try? await Task.sleep(nanoseconds: 800_000_000)
            onResolved()
            dismiss()
        } catch {
            Haptic.error()
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    @MainActor
    private func reject() async {
        isSubmitting = true
        errorMessage = nil
        do {
            _ = try await OrchestratorAPI.reject(
                token: approval.token,
                reason: "사용자 거절"
            )
            Haptic.warning()
            resultMessage = "거절 처리 완료"
            try? await Task.sleep(nanoseconds: 600_000_000)
            onResolved()
            dismiss()
        } catch {
            Haptic.error()
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    // MARK: - Helpers

    private func relativeTimeString(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = fmt.date(from: iso)
        if date == nil {
            fmt.formatOptions = [.withInternetDateTime]
            date = fmt.date(from: iso)
        }
        guard let date else { return nil }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        if seconds < 86400 { return "\(seconds / 3600)시간 전" }
        return "\(seconds / 86400)일 전"
    }
}

// MARK: - Tool kind

private enum ToolKind {
    case email
    case teams
    case commit
    case other
}
