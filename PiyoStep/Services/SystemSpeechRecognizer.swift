import Foundation
import AVFoundation
import Speech
import PiyoCore

/// Speech framework と AVAudioEngine を使った実装。
/// `SpeechRecognizing` に閉じ込めているので、テストではモックに差し替えられる。
final class SystemSpeechRecognizer: NSObject, SpeechRecognizing {

    /// 発話が途切れてから結果を確定するまでの待ち時間
    private let silenceTimeout: TimeInterval = 1.6
    /// 聞き続けるときの 1 区切りの長さ。OS 側の上限があるので長すぎない値にする。
    private let continuousDuration: TimeInterval = 50.0
    private var mode: SpeechListeningMode = .singleAnswer
    /// 1 回の聞き取りの上限
    private let maximumDuration: TimeInterval = 8.0

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private var silenceTimer: Timer?
    private var maximumTimer: Timer?
    private var latestTranscript: String = ""
    private var latestConfidence: Double = 0
    private var hasFinished = true

    private var resultHandler: ((SpeechRecognitionResult) -> Void)?
    private var failureHandler: ((SpeechRecognitionFailure) -> Void)?

    private(set) var audioLevel: Double = 0

    // MARK: - 権限

    var authorizationStatus: SpeechAuthorizationStatus {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let microphone = AVAudioApplication.shared.recordPermission

        switch speech {
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined:
            return microphone == .denied ? .denied : .notDetermined
        case .authorized:
            switch microphone {
            case .granted: return .authorized
            case .denied: return .denied
            case .undetermined: return .notDetermined
            @unknown default: return .notDetermined
            }
        @unknown default:
            return .notDetermined
        }
    }

    func isAvailable(for locale: RecognitionLocale) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.rawValue)) else {
            return false
        }
        return recognizer.isAvailable
    }

    func requestAuthorization(completion: @escaping (SpeechAuthorizationStatus) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            AVAudioApplication.requestRecordPermission { _ in
                DispatchQueue.main.async {
                    completion(self?.authorizationStatus ?? .denied)
                }
            }
        }
    }

    // MARK: - 認識

    func startListening(
        locale: RecognitionLocale,
        mode: SpeechListeningMode,
        onResult: @escaping (SpeechRecognitionResult) -> Void,
        onFailure: @escaping (SpeechRecognitionFailure) -> Void
    ) {
        stopListening()
        self.mode = mode

        resultHandler = onResult
        failureHandler = onFailure
        latestTranscript = ""
        latestConfidence = 0
        hasFinished = false

        guard authorizationStatus == .authorized else {
            deliverFailure(.notAuthorized)
            return
        }
        guard let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.rawValue)),
              speechRecognizer.isAvailable else {
            deliverFailure(.unavailable)
            return
        }
        recognizer = speechRecognizer

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            deliverFailure(.audioEngineFailed)
            return
        }

        let bufferRequest = SFSpeechAudioBufferRecognitionRequest()
        bufferRequest.shouldReportPartialResults = true
        request = bufferRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            deliverFailure(.audioEngineFailed)
            return
        }
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            bufferRequest.append(buffer)
            self?.updateAudioLevel(from: buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            deliverFailure(.audioEngineFailed)
            return
        }

        task = speechRecognizer.recognitionTask(with: bufferRequest) { [weak self] result, error in
            guard let self else { return }
            DispatchQueue.main.async {
                if let result {
                    self.handle(result: result)
                }
                if error != nil, !self.hasFinished {
                    // 音声が拾えなかったケースも含め、ネガティブに扱わない。
                    self.finishWithLatestTranscript()
                }
            }
        }

        scheduleMaximumTimer()
        scheduleSilenceTimer()
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        maximumTimer?.invalidate()
        maximumTimer = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        audioLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 内部

    private func handle(result: SFSpeechRecognitionResult) {
        guard !hasFinished else { return }
        let transcript = result.bestTranscription.formattedString
        latestTranscript = transcript
        latestConfidence = SystemSpeechRecognizer.confidence(of: result)

        resultHandler?(
            SpeechRecognitionResult(
                transcript: transcript,
                confidence: latestConfidence,
                isFinal: false
            )
        )

        if result.isFinal {
            finishWithLatestTranscript()
        } else {
            scheduleSilenceTimer()
        }
    }

    /// セグメントの信頼度の平均。取得できない場合は中庸な値を返す
    /// （認識エンジン側の都合で「不正解」にしないため）。
    static func confidence(of result: SFSpeechRecognitionResult) -> Double {
        let segments = result.bestTranscription.segments
        let values = segments.map { Double($0.confidence) }.filter { $0 > 0 }
        guard !values.isEmpty else { return 0.6 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func scheduleSilenceTimer() {
        // 聞き続けるモードでは無音で打ち切らない。
        // 食事中は静かな時間のほうが長く、打ち切ると言った瞬間を取りこぼす。
        guard mode == .singleAnswer else { return }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            self?.finishWithLatestTranscript()
        }
    }

    private func scheduleMaximumTimer() {
        maximumTimer?.invalidate()
        let duration = mode == .continuous ? continuousDuration : maximumDuration
        maximumTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.finishWithLatestTranscript()
        }
    }

    private func finishWithLatestTranscript() {
        guard !hasFinished else { return }
        hasFinished = true

        let transcript = latestTranscript
        let confidence = latestConfidence
        let onResult = resultHandler
        let onFailure = failureHandler
        stopListening()

        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onFailure?(.noSpeechDetected)
        } else {
            onResult?(
                SpeechRecognitionResult(transcript: transcript, confidence: confidence, isFinal: true)
            )
        }
    }

    private func deliverFailure(_ failure: SpeechRecognitionFailure) {
        hasFinished = true
        let onFailure = failureHandler
        stopListening()
        onFailure?(failure)
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for index in 0 ..< frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }
        let rms = (sum / Float(frameLength)).squareRoot()
        // -50dB 〜 0dB を 0.0 〜 1.0 に写す
        let decibels = 20 * log10(max(rms, 0.000_001))
        let normalized = max(0, min(1, (Double(decibels) + 50) / 50))
        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalized
        }
    }
}
