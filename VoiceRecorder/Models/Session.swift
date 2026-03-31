import Foundation

struct Session: Identifiable, Codable {
    let id: UUID
    let startDate: Date
    var endDate: Date?
    var chunks: [Chunk]
    var status: Status

    enum Status: String, Codable {
        case recording
        case paused
        case completed
    }

    var totalDuration: TimeInterval {
        chunks.reduce(0) { $0 + $1.duration }
    }

    var chunkCount: Int { chunks.count }

    var directoryName: String { id.uuidString }

    init(id: UUID = UUID(), startDate: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.endDate = nil
        self.chunks = []
        self.status = .recording
    }
}
