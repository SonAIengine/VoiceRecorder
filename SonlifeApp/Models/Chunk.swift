import Foundation

struct ChunkLocation: Codable {
    let latitude: Double
    let longitude: Double
    var placemark: String?
}

struct Chunk: Identifiable, Codable {
    let id: UUID
    let sessionId: UUID
    let chunkIndex: Int
    let startDate: Date
    var duration: TimeInterval
    var isSilence: Bool
    var transcript: String?
    var segments: [TranscriptSegment]?
    var location: ChunkLocation?

    struct TranscriptSegment: Codable {
        let start: Double
        let end: Double
        let text: String
        let speaker: String?
    }

    var filename: String {
        String(format: "chunk-%03d.m4a", chunkIndex)
    }

    func url(in sessionDirectory: URL) -> URL {
        sessionDirectory
            .appendingPathComponent(filename)
    }

    init(sessionId: UUID, chunkIndex: Int, startDate: Date = Date(), location: ChunkLocation? = nil) {
        self.id = UUID()
        self.sessionId = sessionId
        self.chunkIndex = chunkIndex
        self.startDate = startDate
        self.duration = 0
        self.isSilence = false
        self.transcript = nil
        self.segments = nil
        self.location = location
    }
}
