import SwiftUI

struct SettingsView: View {
    @State private var serverURL: String = ChunkUploader.shared.currentServerURL
    @State private var testStatus: TestStatus = .idle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
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
        }
        .navigationTitle("설정")
        .navigationBarTitleDisplayMode(.inline)
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

    private enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }
}
