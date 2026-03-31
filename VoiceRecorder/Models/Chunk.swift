import Foundation

struct Chunk: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let chunkIndex: Int
    let startDate: Date
    var duration: TimeInterval
    var isSilence: Bool

    var filename: String {
        String(format: "chunk-%03d.m4a", chunkIndex)
    }

    func url(in baseDirectory: URL) -> URL {
        baseDirectory
            .appendingPathComponent(sessionId.uuidString)
            .appendingPathComponent(filename)
    }

    init(sessionId: UUID, chunkIndex: Int, startDate: Date = Date()) {
        self.id = UUID()
        self.sessionId = sessionId
        self.chunkIndex = chunkIndex
        self.startDate = startDate
        self.duration = 0
        self.isSilence = false
    }
}
