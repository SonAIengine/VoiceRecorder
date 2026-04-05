import SwiftUI

struct FeedbackView: View {
    let sessionId: String
    let summaryPreview: String

    @Environment(\.dismiss) private var dismiss
    @State private var comment: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // 요약 미리보기
                    if !summaryPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("오늘 요약", systemImage: "sparkles")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(summaryPreview)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    // 코멘트 영역
                    VStack(alignment: .leading, spacing: 8) {
                        Text("한 마디 남기기 (선택)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        TextField("어떤 점이 좋았나요? 아쉬웠나요?", text: $comment, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...6)
                    }

                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("요약 피드백")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        sendFeedback(rating: "bad")
                    } label: {
                        Label("개선 필요", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isSending)

                    Button {
                        sendFeedback(rating: "good")
                    } label: {
                        Label("마음에 듦", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSending)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private func sendFeedback(rating: String) {
        isSending = true
        errorMessage = nil
        FeedbackService.sendFeedback(
            sessionId: sessionId,
            rating: rating,
            comment: comment,
            source: "ios-button"
        ) { success in
            isSending = false
            if success {
                dismiss()
            } else {
                errorMessage = "전송 실패. 다시 시도해주세요."
            }
        }
    }
}
