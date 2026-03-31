import Foundation

@Observable
final class SessionManager {
    var sessions: [Session] = []
    var activeSession: Session?

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var sessionsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("LifeLog")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadAllSessions()
    }

    func startSession() -> Session {
        var session = Session()
        let sessionDir = sessionsDirectory.appendingPathComponent(session.directoryName)
        try? fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        activeSession = session
        saveSessionMetadata(session)
        return session
    }

    func addChunk(url: URL, duration: TimeInterval, index: Int) {
        guard var session = activeSession else { return }
        var chunk = Chunk(sessionId: session.id, chunkIndex: index, startDate: Date())
        chunk.duration = duration
        session.chunks.append(chunk)
        activeSession = session
        saveSessionMetadata(session)
    }

    func markChunkAsSilence(index: Int) {
        guard var session = activeSession else { return }
        if let chunkIdx = session.chunks.firstIndex(where: { $0.chunkIndex == index }) {
            session.chunks[chunkIdx].isSilence = true
            activeSession = session
            saveSessionMetadata(session)
        }
    }

    func finalizeSession() {
        guard var session = activeSession else { return }
        session.status = .completed
        session.endDate = Date()
        activeSession = nil
        saveSessionMetadata(session)
        cleanupSilenceChunks(session)
        loadAllSessions()
    }

    func deleteSession(_ session: Session) {
        let sessionDir = sessionsDirectory.appendingPathComponent(session.directoryName)
        try? fileManager.removeItem(at: sessionDir)
        loadAllSessions()
    }

    func chunkURL(for session: Session, index: Int) -> URL {
        sessionsDirectory
            .appendingPathComponent(session.directoryName)
            .appendingPathComponent(String(format: "chunk-%03d.m4a", index))
    }

    func estimatedRemainingHours() -> Double {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let freeBytes = values?.volumeAvailableCapacityForImportantUsage ?? 0
        let bytesPerHour: Double = 14_400_000 // ~14.4MB/hr at 32kbps
        return Double(freeBytes) / bytesPerHour
    }

    // MARK: - Persistence

    private func saveSessionMetadata(_ session: Session) {
        let dir = sessionsDirectory.appendingPathComponent(session.directoryName)
        let metaURL = dir.appendingPathComponent("session.json")
        if let data = try? encoder.encode(session) {
            try? data.write(to: metaURL, options: .atomic)
        }
    }

    func loadAllSessions() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            sessions = []
            return
        }

        sessions = contents
            .compactMap { dir -> Session? in
                let metaURL = dir.appendingPathComponent("session.json")
                guard let data = try? Data(contentsOf: metaURL) else { return nil }
                return try? decoder.decode(Session.self, from: data)
            }
            .sorted { $0.startDate > $1.startDate }
    }

    private func cleanupSilenceChunks(_ session: Session) {
        let sessionDir = sessionsDirectory.appendingPathComponent(session.directoryName)
        for chunk in session.chunks where chunk.isSilence {
            let chunkURL = sessionDir.appendingPathComponent(chunk.filename)
            try? fileManager.removeItem(at: chunkURL)
        }
    }
}
