import Foundation
import UIKit

enum FeedbackService {
    // 기존 ChunkUploader와 동일한 서버 URL 설정 재사용
    static var serverURL: String {
        ChunkUploader.shared.currentServerURL
    }

    static var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    /// APNs 디바이스 토큰을 서버에 등록
    static func registerDevice(token: String) {
        guard let url = URL(string: serverURL)?.appendingPathComponent("api/devices/register") else {
            print("[FeedbackService] 잘못된 serverURL: \(serverURL)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "device_id": deviceId,
            "device_token": token,
            "platform": "ios",
            "supported_categories": ["APPROVAL_REQUEST", "FEEDBACK_REQUEST", "BRIEFING"],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("[FeedbackService] 디바이스 등록 실패: \(error.localizedDescription)")
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("[FeedbackService] 디바이스 등록 완료: HTTP \(status)")
            }
        }.resume()
    }

    /// 사용자 피드백 서버에 전송
    static func sendFeedback(
        sessionId: String,
        rating: String?,
        comment: String = "",
        source: String = "ios-button",
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = URL(string: serverURL)?.appendingPathComponent("api/feedback") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "session_id": sessionId,
            "comment": comment,
            "source": source,
        ]
        if let rating = rating {
            body["rating"] = rating
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, error in
            let success = (response as? HTTPURLResponse)?.statusCode == 200
            if let error = error {
                print("[FeedbackService] 피드백 전송 실패: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion(success) }
        }.resume()
    }
}
