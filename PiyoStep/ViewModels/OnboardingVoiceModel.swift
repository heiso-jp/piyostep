import Foundation
import Observation
import PiyoCore

/// はじめての設定で使う音声入力。
///
/// 3〜6 歳は字が読めない・打てないことが多いので、なまえと ねんれい を最初から声で
/// 入れられるようにする。キーボードや数字ボタンでの入力も今までどおり残す。
@MainActor
@Observable
final class OnboardingVoiceModel {

    /// いま聞き取ろうとしている項目。
    enum Field: Equatable {
        case name
        case age

        var prompt: String {
            switch self {
            case .name: return "なまえを おしえてね"
            case .age: return "なんさい？"
            }
        }
    }

    enum State: Equatable {
        case idle
        case requestingPermission
        case listening
        /// 聞き取れて、入力に反映できた
        case accepted(String)
        /// 声は届いたが、なまえ・ねんれい として読み取れなかった
        case unclear
        /// マイクが使えない（未許可・非対応・設定でオフ）
        case unavailable
    }

    private let environment: AppEnvironment
    private var levelTimer: Timer?
    private var autoStartTask: Task<Void, Never>?

    private(set) var field: Field = .name
    private(set) var state: State = .idle
    /// 認識中のことば（画面に薄く出す）
    private(set) var transcript: String = ""
    private(set) var level: Double = 0
    /// 聞き取れなかった回数。続いたら手入力をすすめる。
    private(set) var unclearCount = 0

    /// 聞き取れた内容の受け取り先。画面側で入力欄に反映する。
    var onName: (String) -> Void = { _ in }
    var onAge: (Int) -> Void = { _ in }

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // MARK: - 状態

    var isListening: Bool { state == .listening }

    /// この端末でマイクを使えるか（設定でオフにされていないかも見る）。
    var isAvailable: Bool { environment.canUseVoice(for: .japanese) }

    /// キーボード・ボタンでの入力をすすめるべきか。
    var shouldSuggestManualInput: Bool {
        state == .unavailable || unclearCount >= 2
    }

    /// マイクの下に出す案内。ネガティブな言い方にはしない。
    var guidanceText: String {
        switch state {
        case .idle:
            return "マイクを おして はなしてね"
        case .requestingPermission:
            return "マイクを つかっても いい？"
        case .listening:
            return "はなしてね"
        case .accepted(let text):
            return "「\(text)」 だね！"
        case .unclear:
            return unclearCount >= 2 ? "したから えらんでも いいよ" : "もういちど いってみよう！"
        case .unavailable:
            return "したから いれてね"
        }
    }

    // MARK: - 進行

    /// ステップが切り替わったときに呼ぶ。案内を読み上げてから、使えるなら自動で聞き始める。
    func begin(field newField: Field, speakPrompt: Bool = true) {
        stop()
        autoStartTask?.cancel()
        field = newField
        state = .idle
        transcript = ""
        unclearCount = 0
        level = 0

        if speakPrompt {
            environment.speak(newField.prompt)
        }
        guard isAvailable else {
            state = .unavailable
            return
        }
        // 許可済みのときだけ自動で開く。未許可のときにいきなり
        // システムの確認ダイアログを出すと、理由が分からないまま断られてしまう。
        guard environment.speechRecognizer.authorizationStatus == .authorized else { return }

        autoStartTask = Task { [weak self] in
            // 案内の読み上げが終わるのを待ってから聞き始める。
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }

    func toggle() {
        if isListening {
            stop()
        } else {
            start()
        }
    }

    func start() {
        autoStartTask?.cancel()
        guard isAvailable else {
            state = .unavailable
            return
        }
        environment.stopSpeaking()

        let recognizer = environment.speechRecognizer
        switch recognizer.authorizationStatus {
        case .authorized:
            beginListening()
        case .notDetermined:
            state = .requestingPermission
            recognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    if status == .authorized {
                        self.beginListening()
                    } else {
                        self.state = .unavailable
                    }
                }
            }
        case .denied, .restricted, .unavailable:
            state = .unavailable
        }
    }

    func stop() {
        autoStartTask?.cancel()
        stopLevelTimer()
        environment.speechRecognizer.stopListening()
        if isListening {
            state = .idle
        }
    }

    // MARK: - 認識

    private func beginListening() {
        state = .listening
        transcript = ""
        environment.play(.listenStart)
        startLevelTimer()

        environment.speechRecognizer.startListening(
            locale: .japanese,
            onResult: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.transcript = result.transcript
                    if result.isFinal {
                        self.handleFinal(result.transcript)
                    }
                }
            },
            onFailure: { [weak self] failure in
                Task { @MainActor in
                    guard let self else { return }
                    self.stopLevelTimer()
                    self.environment.play(.listenEnd)
                    switch failure {
                    case .notAuthorized, .unavailable:
                        self.state = .unavailable
                    case .noSpeechDetected, .audioEngineFailed, .cancelled, .other:
                        self.markUnclear()
                    }
                }
            }
        )
    }

    private func handleFinal(_ transcript: String) {
        stopLevelTimer()
        environment.play(.listenEnd)

        switch field {
        case .name:
            guard let name = SpokenProfileParser.name(from: transcript) else {
                markUnclear()
                return
            }
            unclearCount = 0
            state = .accepted(name)
            onName(name)
            environment.haptics.success()
            environment.speak("\(name) だね！")

        case .age:
            guard let age = SpokenProfileParser.age(from: transcript) else {
                markUnclear()
                return
            }
            unclearCount = 0
            state = .accepted("\(age)さい")
            onAge(age)
            environment.haptics.success()
            environment.speak("\(age)さい だね！")
        }
    }

    private func markUnclear() {
        unclearCount += 1
        state = .unclear
        environment.speak(guidanceText)
    }

    // MARK: - 入力レベル（波形表示用）

    private func startLevelTimer() {
        stopLevelTimer()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.level = self.environment.speechRecognizer.audioLevel
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
    }
}
