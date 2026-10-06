import Foundation
import Observation
import PiyoCore

/// 学習セッション（今日のチャレンジ / 教科ごとの練習）の画面ロジック。
@MainActor
@Observable
final class SessionViewModel {

    enum Stage: Equatable {
        case asking
        case feedback
        case finished
    }

    /// 時刻入力でいま編集している欄。
    enum TimeField: Equatable {
        case hour
        case minute
    }

    private let environment: AppEnvironment
    private let engine: LearningSessionEngine

    let kind: SessionKind
    let subject: Subject?
    let questions: [Question]

    /// いま出ている問題。
    /// LearningSessionEngine は @Observable ではないため、computed のままだと
    /// 問題が進んでも SwiftUI が変化に気づけず、選択肢が前の問題のまま残る。
    private(set) var currentQuestion: Question?
    private(set) var stage: Stage = .asking
    private(set) var feedback: SessionFeedback?
    private(set) var summary: SessionSummary?
    private(set) var currentIndex: Int = 0

    /// いま選ばれている回答方法
    var answerMode: AnswerMode = .choice
    /// 数字入力
    var numberInput: String = ""
    /// 時刻入力
    var hourInput: String = ""
    var minuteInput: String = ""
    var activeTimeField: TimeField = .hour
    /// 時計の針の現在位置
    var draggedTime: ClockTime = ClockTime(hour: 12, minute: 0)
    /// なぞり書き
    var traceStrokes: [[TracePoint]] = []
    /// 数えるときのタップ印
    var countedIndices: Set<Int> = []

    var showsHint: Bool = false
    var showsConfetti: Bool = false
    var selectedChoiceID: UUID?

    // 音声
    let voiceCoordinator = VoiceAnswerCoordinator()
    private(set) var voiceState: VoiceAnswerState = .idle
    private(set) var voiceLevel: Double = 0
    private(set) var voiceTranscript: String = ""
    private var levelTimer: Timer?

    init(environment: AppEnvironment, kind: SessionKind, subject: Subject?, questions: [Question]) {
        self.environment = environment
        self.kind = kind
        self.subject = subject
        self.questions = questions
        self.engine = LearningSessionEngine(
            kind: kind,
            subject: subject,
            questions: questions,
            clock: environment.clock
        )
    }

    // MARK: - 進行

    var progressCount: Int { currentIndex }
    var totalCount: Int { questions.count }

    var availableModes: [AnswerMode] {
        guard let question = currentQuestion else { return [] }
        var modes = question.answerModes
        if !environment.canUseVoice(for: question.answer.locale) {
            modes.removeAll { $0 == .voice }
        }
        return modes
    }

    var visibleChoices: [AnswerChoice] {
        guard let question = currentQuestion else { return [] }
        return showsHint ? question.narrowedChoices(to: 2) : question.choices
    }

    func start() {
        environment.adPresenter.isLearningSessionActive = true
        _ = engine.start()
        prepareForCurrentQuestion(speakPrompt: true)
    }

    func close() {
        stopVoice()
        environment.adPresenter.isLearningSessionActive = false
        environment.stopSpeaking()
        if !engine.isCompleted {
            let earlySummary = engine.finishEarly()
            if !earlySummary.attempts.isEmpty {
                environment.process(summary: earlySummary)
            }
        }
    }

    func advance() {
        stopVoice()
        showsConfetti = false
        let phase = engine.advance()
        currentIndex = engine.currentIndex
        if case let .completed(result) = phase {
            finish(with: result)
        } else {
            prepareForCurrentQuestion(speakPrompt: true)
        }
    }

    func retryCurrentQuestion() {
        stopVoice()
        _ = engine.retry()
        currentQuestion = engine.currentQuestion
        showsHint = true
        selectedChoiceID = nil
        numberInput = ""
        hourInput = ""
        minuteInput = ""
        activeTimeField = .hour
        traceStrokes = []
        countedIndices = []
        stage = .asking
        feedback = nil
        speakPrompt(includeHint: true)
    }

    func speakPrompt(includeHint: Bool = false) {
        guard let question = currentQuestion else { return }
        var text = question.prompt.spokenText
        if includeHint, let hint = question.prompt.hintText {
            text += " " + hint
        }
        environment.speak(text, locale: question.answer.locale == .englishUS ? .englishUS : .japanese)
    }

    /// 選択肢や文字を読み上げる（子どもが文字を読めなくても分かるように）。
    func speak(choice: AnswerChoice) {
        guard let question = currentQuestion else { return }
        environment.speak(choice.spokenText, locale: question.answer.locale)
    }

    private func prepareForCurrentQuestion(speakPrompt shouldSpeak: Bool) {
        currentQuestion = engine.currentQuestion
        currentIndex = engine.currentIndex
        stage = .asking
        feedback = nil
        showsHint = false
        selectedChoiceID = nil
        numberInput = ""
        hourInput = ""
        minuteInput = ""
        activeTimeField = .hour
        traceStrokes = []
        countedIndices = []
        voiceCoordinator.reset()
        voiceState = .idle
        voiceTranscript = ""

        if let question = currentQuestion {
            answerMode = availableModes.first ?? question.answerModes.first ?? .choice
            if case let .clockSet(_, start, _) = question.content {
                draggedTime = start
            } else {
                draggedTime = ClockTime(hour: 12, minute: 0)
            }
        }
        if shouldSpeak {
            speakPrompt()
        }
    }

    private func finish(with result: SessionSummary) {
        currentQuestion = nil
        summary = result
        stage = .finished
        environment.adPresenter.isLearningSessionActive = false
        environment.process(summary: result)
        environment.play(.star)
    }

    // MARK: - 回答

    func select(choice: AnswerChoice) {
        selectedChoiceID = choice.id
        environment.haptics.tap()
        submit(.choice(id: choice.id))
    }

    func submitNumberInput() {
        guard let value = Int(numberInput) else { return }
        submit(.integer(value))
    }

    func submitTimeInput() {
        guard let hour = Int(hourInput.isEmpty ? "0" : hourInput) else { return }
        let minute = Int(minuteInput.isEmpty ? "0" : minuteInput) ?? 0
        submit(.time(ClockTime(hour: hour, minute: minute)))
    }

    func submitDraggedTime() {
        submit(.time(draggedTime))
    }

    func submitTrace() {
        guard let question = currentQuestion else { return }
        let text = AnswerGrader.correctAnswerDisplay(for: question)
        let mask = GlyphMaskRenderer.mask(for: text)
        let evaluation = TraceEvaluator.evaluate(
            mask: mask,
            strokes: traceStrokes,
            brushRadius: 0.075,
            expectedStrokeCount: question.expectedStrokeCount
        )
        submit(.trace(coverage: evaluation.score))
    }

    func skip() {
        submit(.skipped)
    }

    func appendDigit(_ digit: Int) {
        environment.haptics.tap()
        guard let question = currentQuestion else { return }
        if question.subject == .clock {
            switch activeTimeField {
            case .hour:
                hourInput = String((hourInput + "\(digit)").suffix(2))
            case .minute:
                minuteInput = String((minuteInput + "\(digit)").suffix(2))
            }
        } else {
            numberInput = String((numberInput + "\(digit)").suffix(3))
        }
    }

    func clearInput() {
        numberInput = ""
        hourInput = ""
        minuteInput = ""
        activeTimeField = .hour
    }

    func toggleCounted(index: Int) {
        if countedIndices.contains(index) {
            countedIndices.remove(index)
        } else {
            countedIndices.insert(index)
            environment.haptics.softNudge()
        }
    }

    private func submit(_ input: AnswerInput) {
        guard currentQuestion != nil else { return }
        let result = engine.submit(input)
        feedback = result
        stage = .feedback

        switch result.judgement {
        case .correct:
            showsConfetti = true
            environment.play(.correct)
            environment.haptics.success()
        case .incorrect:
            environment.play(.incorrect)
            environment.haptics.softNudge()
        case .unclear:
            break
        }
        environment.speak(result.message)
    }

    // MARK: - 音声

    var isVoiceAvailable: Bool {
        guard let question = currentQuestion else { return false }
        return question.answerModes.contains(.voice)
            && environment.canUseVoice(for: question.answer.locale)
    }

    var shouldSuggestTapAnswer: Bool {
        voiceCoordinator.shouldSuggestTapAnswer
    }

    var voiceGuidanceText: String {
        voiceCoordinator.guidanceText
    }

    func startVoice() {
        guard let question = currentQuestion else { return }
        environment.stopSpeaking()

        let locale = question.answer.locale
        let recognizer = environment.speechRecognizer
        let state = voiceCoordinator.begin(
            authorization: recognizer.authorizationStatus,
            isAvailable: recognizer.isAvailable(for: locale)
        )
        voiceState = state

        switch state {
        case .requestingPermission:
            recognizer.requestAuthorization { [weak self] status in
                Task { @MainActor in
                    guard let self else { return }
                    self.voiceState = self.voiceCoordinator.handleAuthorization(status)
                    if self.voiceState == .listening {
                        self.beginListening(locale: locale)
                    }
                }
            }
        case .listening:
            beginListening(locale: locale)
        default:
            break
        }
    }

    private func beginListening(locale: RecognitionLocale) {
        environment.play(.listenStart)
        voiceTranscript = ""
        startLevelTimer()

        environment.speechRecognizer.startListening(
            locale: locale,
            onResult: { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    if result.isFinal {
                        self.handleFinalTranscript(result)
                    } else {
                        self.voiceCoordinator.handlePartial(transcript: result.transcript)
                        self.voiceTranscript = result.transcript
                    }
                }
            },
            onFailure: { [weak self] failure in
                Task { @MainActor in
                    guard let self else { return }
                    self.stopLevelTimer()
                    self.voiceState = self.voiceCoordinator.handleFailure(failure)
                    self.environment.play(.listenEnd)
                    if case .finished(.unclear) = self.voiceState {
                        self.environment.speak(self.voiceCoordinator.retryMessage())
                    }
                }
            }
        )
    }

    private func handleFinalTranscript(_ result: SpeechRecognitionResult) {
        guard let question = currentQuestion else { return }
        stopLevelTimer()
        environment.play(.listenEnd)
        voiceTranscript = result.transcript

        let evaluation = voiceCoordinator.handleFinal(
            transcript: result.transcript,
            confidence: result.confidence,
            question: question
        )
        voiceState = .finished(evaluation.judgement)

        if evaluation.judgement == .unclear {
            // 認識できなかっただけなので、学習の不正解にはしない。
            environment.speak(voiceCoordinator.retryMessage())
            return
        }
        submit(.speech(transcript: result.transcript, confidence: result.confidence))
    }

    func stopVoice() {
        stopLevelTimer()
        environment.speechRecognizer.stopListening()
        if case .listening = voiceState {
            voiceState = .idle
        }
    }

    private func startLevelTimer() {
        stopLevelTimer()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.voiceLevel = self.environment.speechRecognizer.audioLevel
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        voiceLevel = 0
    }
}

extension ExpectedAnswer {
    /// 回答に使う言語。
    var locale: RecognitionLocale {
        switch self {
        case .text(_, _, let locale): return locale
        case .time, .integer, .trace: return .japanese
        }
    }
}
