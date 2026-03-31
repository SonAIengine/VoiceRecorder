import AVFoundation
import Speech

@Observable
final class AudioRecorder: RecordingEngineDelegate, VADMonitorDelegate, AudioSessionHandlerDelegate {
    // Manual mode state
    var isRecording = false
    var isPaused = false
    var recordings: [Recording] = []
    var currentTime: TimeInterval = 0
    var errorMessage: String?

    // LifeLog state
    var isLifeLogActive = false
    var lifeLogSessionTime: TimeInterval = 0
    var currentPowerLevel: Float = -160.0
    var vadState: VADState = .active
    var vadSilenceDuration: TimeInterval = 0

    // Components
    private let engine = RecordingEngine()
    private let vad = VADMonitor()
    let sessionManager = SessionManager()
    private let audioSessionHandler = AudioSessionHandler()

    // Manual mode internals
    private var manualRecorder: AVAudioRecorder?
    private var timer: Timer?
    private let fileManager = FileManager.default

    var recordingsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings")
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        engine.delegate = self
        vad.delegate = self
        audioSessionHandler.delegate = self
        loadRecordings()
    }

    // MARK: - LifeLog Mode

    func startLifeLog() {
        do {
            try audioSessionHandler.configure()
        } catch {
            errorMessage = "오디오 세션 설정 실패: \(error.localizedDescription)"
            return
        }

        let session = sessionManager.startSession()
        isLifeLogActive = true
        lifeLogSessionTime = 0

        engine.start { [weak self] index in
            guard let self, let activeSession = self.sessionManager.activeSession else {
                return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp.m4a")
            }
            return self.sessionManager.chunkURL(for: activeSession, index: index)
        }

        vad.start(engine: engine)

        // LifeLog 시간 업데이트 타이머
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.lifeLogSessionTime = (self.sessionManager.activeSession?.totalDuration ?? 0) + self.engine.currentTime
            self.vadSilenceDuration = self.vad.silenceDuration
        }
    }

    func stopLifeLog() {
        vad.stop()
        engine.stop()
        timer?.invalidate()
        timer = nil
        sessionManager.finalizeSession()
        isLifeLogActive = false
        lifeLogSessionTime = 0
        currentPowerLevel = -160.0
        vadState = .active
    }

    // MARK: - RecordingEngineDelegate

    func engineDidFinishChunk(url: URL, duration: TimeInterval, index: Int) {
        sessionManager.addChunk(url: url, duration: duration, index: index)
    }

    func engineDidUpdateMeters(averagePower: Float, peakPower: Float) {
        currentPowerLevel = averagePower
    }

    func engineDidEncounterError(_ error: Error) {
        errorMessage = "녹음 엔진 오류: \(error.localizedDescription)"
    }

    // MARK: - VADMonitorDelegate

    func vadDidDetectSilence() {
        // 무음 감지 → 현재 청크를 silence로 마킹
        // 녹음은 계속 유지 (미터링 위해)
    }

    func vadDidDetectVoice() {
        // 소리 재감지 → 새 청크 시작 (무음 구간 분리)
        engine.splitNow()
        vad.reset()
    }

    func vadStateDidChange(_ state: VADState) {
        vadState = state
    }

    // MARK: - AudioSessionHandlerDelegate

    func audioSessionWasInterrupted() {
        if isLifeLogActive {
            // 전화 등 인터럽션 → 현재 청크 종료, 일시 정지 상태
            engine.stop()
            vad.stop()
            timer?.invalidate()
        }
    }

    func audioSessionInterruptionEnded(shouldResume: Bool) {
        if isLifeLogActive && shouldResume {
            // 인터럽션 종료 → 녹음 재개
            guard let session = sessionManager.activeSession else { return }
            let nextIndex = session.chunkCount

            engine.start { [weak self] index in
                guard let self, let activeSession = self.sessionManager.activeSession else {
                    return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("temp.m4a")
                }
                return self.sessionManager.chunkURL(for: activeSession, index: nextIndex + index)
            }

            vad.start(engine: engine)

            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.lifeLogSessionTime = (self.sessionManager.activeSession?.totalDuration ?? 0) + self.engine.currentTime
                self.vadSilenceDuration = self.vad.silenceDuration
            }
        }
    }

    func audioRouteChanged(event: AudioRouteChangeEvent) {
        // 이어폰 탈착 시 녹음은 자동으로 내장 마이크로 전환됨 (iOS 기본 동작)
        // 별도 처리 불필요
    }

    // MARK: - Manual Recording Mode (기존 유지)

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            errorMessage = "오디오 세션 설정 실패: \(error.localizedDescription)"
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = recordingsDirectory.appendingPathComponent("\(timestamp).m4a")

        do {
            manualRecorder = try AVAudioRecorder(url: filename, settings: RecordingEngine.manualSettings)
            manualRecorder?.record()
            isRecording = true
            isPaused = false
            currentTime = 0
            startManualTimer()
        } catch {
            errorMessage = "녹음 시작 실패: \(error.localizedDescription)"
        }
    }

    func pauseRecording() {
        manualRecorder?.pause()
        isPaused = true
        timer?.invalidate()
    }

    func resumeRecording() {
        manualRecorder?.record()
        isPaused = false
        startManualTimer()
    }

    func stopRecording() {
        guard let recorder = manualRecorder else { return }
        let url = recorder.url
        recorder.stop()
        timer?.invalidate()
        isRecording = false
        isPaused = false
        currentTime = 0
        manualRecorder = nil
        loadRecordings()
        transcribe(url: url)
    }

    func deleteRecording(_ recording: Recording) {
        try? fileManager.removeItem(at: recording.url)
        if let txtURL = recording.transcriptURL {
            try? fileManager.removeItem(at: txtURL)
        }
        loadRecordings()
    }

    func loadRecordings() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            recordings = []
            return
        }

        recordings = files
            .filter { $0.pathExtension == "m4a" }
            .compactMap { url -> Recording? in
                let attrs = try? fileManager.attributesOfItem(atPath: url.path)
                let date = attrs?[.creationDate] as? Date ?? Date()
                let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
                let hasTranscript = fileManager.fileExists(atPath: txtURL.path)
                let transcript = hasTranscript ? (try? String(contentsOf: txtURL, encoding: .utf8)) : nil
                return Recording(url: url, date: date, transcript: transcript)
            }
            .sorted { $0.date > $1.date }
    }

    // MARK: - Private (Manual Mode)

    private func startManualTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.manualRecorder else { return }
            self.currentTime = recorder.currentTime
        }
    }

    private func transcribe(url: URL) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.errorMessage = "음성 인식 권한이 필요합니다."
                }
                return
            }

            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
                ?? SFSpeechRecognizer()

            guard let recognizer, recognizer.isAvailable else {
                DispatchQueue.main.async {
                    self.errorMessage = "음성 인식을 사용할 수 없습니다."
                }
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
                    try? text.write(to: txtURL, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.loadRecordings()
                    }
                } else if let error {
                    DispatchQueue.main.async {
                        self.errorMessage = "STT 변환 실패: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
