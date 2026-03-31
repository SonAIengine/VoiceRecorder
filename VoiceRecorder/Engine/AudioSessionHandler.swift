import AVFoundation

enum AudioRouteChangeEvent {
    case headphonesConnected
    case headphonesDisconnected
}

protocol AudioSessionHandlerDelegate: AnyObject {
    func audioSessionWasInterrupted()
    func audioSessionInterruptionEnded(shouldResume: Bool)
    func audioRouteChanged(event: AudioRouteChangeEvent)
}

final class AudioSessionHandler {
    weak var delegate: AudioSessionHandlerDelegate?

    func configure() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    func deactivate() {
        NotificationCenter.default.removeObserver(self)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc private func handleInterruption(notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            delegate?.audioSessionWasInterrupted()
        case .ended:
            let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            delegate?.audioSessionInterruptionEnded(shouldResume: shouldResume)
        @unknown default:
            break
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let info = notification.userInfo,
              let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        switch reason {
        case .oldDeviceUnavailable:
            delegate?.audioRouteChanged(event: .headphonesDisconnected)
        case .newDeviceAvailable:
            delegate?.audioRouteChanged(event: .headphonesConnected)
        default:
            break
        }
    }
}
