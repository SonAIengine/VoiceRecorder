import SwiftUI
import UserNotifications

@main
struct SonlifeAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @AppStorage("appTheme") private var selectedTheme: String = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppTheme(rawValue: selectedTheme)?.colorScheme)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    // MARK: - Notification Categories & Actions (Identifier constants)

    private enum NotificationCategory {
        static let approvalRequest = "APPROVAL_REQUEST"
        static let feedbackRequest = "FEEDBACK_REQUEST"
        static let briefing = "BRIEFING"
    }

    private enum NotificationAction {
        static let approve = "APPROVE_ACTION"
        static let reject = "REJECT_ACTION"
        static let open = "OPEN_ACTION"
        static let detail = "DETAIL_ACTION"
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // APPROVAL_REQUEST 카테고리 — Phase A HITL 승인 (승인/거절 인라인 액션)
        let approveAction = UNNotificationAction(
            identifier: NotificationAction.approve,
            title: "승인",
            options: [.authenticationRequired, .foreground]
        )
        let rejectAction = UNNotificationAction(
            identifier: NotificationAction.reject,
            title: "거절",
            options: [.destructive, .foreground]
        )
        let openAction = UNNotificationAction(
            identifier: NotificationAction.open,
            title: "열기",
            options: [.foreground]
        )
        let approvalCategory = UNNotificationCategory(
            identifier: NotificationCategory.approvalRequest,
            actions: [approveAction, openAction, rejectAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // FEEDBACK_REQUEST 카테고리 — 기존 H3-A
        let feedbackCategory = UNNotificationCategory(
            identifier: NotificationCategory.feedbackRequest,
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )

        // BRIEFING 카테고리 — 브리핑/요약 알림
        let detailAction = UNNotificationAction(
            identifier: NotificationAction.detail,
            title: "자세히",
            options: [.foreground]
        )
        let briefingCategory = UNNotificationCategory(
            identifier: NotificationCategory.briefing,
            actions: [detailAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([approvalCategory, feedbackCategory, briefingCategory])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[APNs] 권한 요청 에러: \(error.localizedDescription)")
            }
            if granted {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            } else {
                print("[APNs] 알림 권한 거부됨")
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("[APNs] token: \(tokenString)")
        FeedbackService.registerDevice(token: tokenString)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] 등록 실패: \(error.localizedDescription)")
    }

    // 포그라운드 수신
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // 푸시 탭/액션 핸들러
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier
        let type = (userInfo["type"] as? String) ?? ""

        switch type {
        case "feedback_request":
            if let sessionId = userInfo["session_id"] as? String {
                let summary = userInfo["summary_preview"] as? String ?? ""
                NotificationCenter.default.post(
                    name: .showFeedback,
                    object: nil,
                    userInfo: ["session_id": sessionId, "summary": summary]
                )
            }

        case "approval_request":
            guard let token = userInfo["token"] as? String else {
                completionHandler()
                return
            }

            // 인라인 액션 처리
            if actionId == NotificationAction.approve {
                // Face ID 인증 후 즉시 승인 (authenticationRequired 옵션이 처리)
                Task {
                    _ = try? await OrchestratorAPI.approve(token: token, modifiedArgs: nil)
                }
            } else if actionId == NotificationAction.reject {
                Task {
                    _ = try? await OrchestratorAPI.reject(token: token, reason: "알림에서 거절")
                }
            } else {
                // "열기" 또는 기본 탭 → ApprovalSheetView 오픈
                NotificationCenter.default.post(
                    name: .showApproval,
                    object: nil,
                    userInfo: ["token": token]
                )
            }

        case "briefing":
            if actionId == NotificationAction.detail || actionId == UNNotificationDefaultActionIdentifier {
                let sessionId = userInfo["session_id"] as? String
                let briefingId = userInfo["briefing_id"] as? String
                NotificationCenter.default.post(
                    name: .showBriefingDetail,
                    object: nil,
                    userInfo: [
                        "session_id": sessionId ?? "",
                        "briefing_id": briefingId ?? "",
                    ]
                )
            }

        default:
            break
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let showFeedback = Notification.Name("SonLifeShowFeedback")
    static let showApproval = Notification.Name("SonLifeShowApproval")
    static let showBriefingDetail = Notification.Name("SonLifeShowBriefingDetail")
}
