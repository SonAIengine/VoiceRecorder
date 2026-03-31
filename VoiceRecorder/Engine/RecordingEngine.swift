import AVFoundation

protocol RecordingEngineDelegate: AnyObject {
    func engineDidFinishChunk(url: URL, duration: TimeInterval, index: Int)
    func engineDidUpdateMeters(averagePower: Float, peakPower: Float)
    func engineDidEncounterError(_ error: Error)
}

final class RecordingEngine {
    weak var delegate: RecordingEngineDelegate?

    private(set) var isRecording = false
    private var currentRecorder: AVAudioRecorder?
    private var nextRecorder: AVAudioRecorder?
    private var meteringTimer: Timer?
    private var chunkTimer: Timer?
    private var currentChunkStartTime: Date?
    private var currentChunkIndex = 0
    private var currentChunkURL: URL?
    private var chunkDuration: TimeInterval
    private var audioSettings: [String: Any]
    private var urlProvider: ((Int) -> URL)?

    // STT 최적화 설정: 16kHz mono AAC 32kbps (~14.4MB/hour)
    static let lifeLogSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        AVEncoderBitRateKey: 32000
    ]

    // 수동 녹음용: 44.1kHz mono AAC high quality
    static let manualSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    init(chunkDuration: TimeInterval = 300, audioSettings: [String: Any] = lifeLogSettings) {
        self.chunkDuration = chunkDuration
        self.audioSettings = audioSettings
    }

    func start(urlProvider: @escaping (Int) -> URL) {
        self.urlProvider = urlProvider
        currentChunkIndex = 0
        startChunk(index: 0)

        // 미터링 타이머 (10Hz)
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateMeters()
        }

        // 청크 분할 타이머 (0.25초마다 체크)
        chunkTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkChunkSplit()
        }

        isRecording = true
    }

    func stop() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        chunkTimer?.invalidate()
        chunkTimer = nil

        finalizeCurrentChunk()
        nextRecorder?.stop()
        nextRecorder = nil
        isRecording = false
    }

    func currentAveragePower() -> Float {
        currentRecorder?.updateMeters()
        return currentRecorder?.averagePower(forChannel: 0) ?? -160.0
    }

    func currentPeakPower() -> Float {
        currentRecorder?.updateMeters()
        return currentRecorder?.peakPower(forChannel: 0) ?? -160.0
    }

    var currentTime: TimeInterval {
        currentRecorder?.currentTime ?? 0
    }

    // 현재 청크를 종료하고 새 청크 시작 (VAD에서 호출)
    func splitNow() {
        let nextIndex = currentChunkIndex + 1
        finalizeCurrentChunk()
        startChunk(index: nextIndex)
    }

    // MARK: - Private

    private func startChunk(index: Int) {
        guard let urlProvider else { return }
        let url = urlProvider(index)
        currentChunkIndex = index

        do {
            let recorder = try AVAudioRecorder(url: url, settings: audioSettings)
            recorder.isMeteringEnabled = true
            recorder.prepareToRecord()
            recorder.record()
            currentRecorder = recorder
            currentChunkURL = url
            currentChunkStartTime = Date()
        } catch {
            delegate?.engineDidEncounterError(error)
        }
    }

    private func finalizeCurrentChunk() {
        guard let recorder = currentRecorder,
              let url = currentChunkURL,
              let startTime = currentChunkStartTime else { return }

        let duration = recorder.currentTime
        recorder.stop()
        currentRecorder = nil

        if duration > 0.5 { // 0.5초 미만 청크는 버림
            delegate?.engineDidFinishChunk(url: url, duration: duration, index: currentChunkIndex)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func checkChunkSplit() {
        guard let recorder = currentRecorder else { return }
        if recorder.currentTime >= chunkDuration {
            // Gapless split: 새 recorder 먼저 시작 → 기존 stop
            let nextIndex = currentChunkIndex + 1
            guard let urlProvider else { return }
            let nextURL = urlProvider(nextIndex)

            do {
                let next = try AVAudioRecorder(url: nextURL, settings: audioSettings)
                next.isMeteringEnabled = true
                next.prepareToRecord()
                next.record() // 새 녹음 먼저 시작

                // 기존 청크 종료
                let duration = recorder.currentTime
                let url = currentChunkURL
                recorder.stop()

                if duration > 0.5, let url {
                    delegate?.engineDidFinishChunk(url: url, duration: duration, index: currentChunkIndex)
                }

                // 스왑
                currentRecorder = next
                currentChunkURL = nextURL
                currentChunkStartTime = Date()
                currentChunkIndex = nextIndex
            } catch {
                delegate?.engineDidEncounterError(error)
            }
        }
    }

    private func updateMeters() {
        guard let recorder = currentRecorder else { return }
        recorder.updateMeters()
        let avg = recorder.averagePower(forChannel: 0)
        let peak = recorder.peakPower(forChannel: 0)
        delegate?.engineDidUpdateMeters(averagePower: avg, peakPower: peak)
    }
}
