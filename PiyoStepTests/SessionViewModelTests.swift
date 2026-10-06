import XCTest
import PiyoCore
@testable import PiyoStep

@MainActor
final class SessionViewModelTests: XCTestCase {

    private func makeModel(
        environment: AppEnvironment,
        questions: [Question]
    ) -> SessionViewModel {
        let model = SessionViewModel(
            environment: environment,
            kind: .dailyChallenge,
            subject: nil,
            questions: questions
        )
        model.start()
        return model
    }

    func testStartPresentsFirstQuestion() {
        let environment = TestEnvironment.make()
        let model = makeModel(
            environment: environment,
            questions: [TestEnvironment.integerQuestion(correct: 3)]
        )
        XCTAssertEqual(model.stage, .asking)
        XCTAssertEqual(model.currentQuestion?.answer, .integer(3))
        XCTAssertEqual(model.totalCount, 1)
        XCTAssertEqual(model.progressCount, 0)
    }

    func testStartReadsThePromptAloud() {
        let synthesizer = MockSpeechSynthesizer()
        let environment = TestEnvironment.make(synthesizer: synthesizer)
        _ = makeModel(environment: environment, questions: [TestEnvironment.integerQuestion()])
        XCTAssertTrue(synthesizer.spokenTexts.contains("いくつ かな？"))
    }

    func testVoiceGuidanceCanBeSilenced() {
        var settings = AppSettings.default
        settings.voiceGuidanceEnabled = false
        let synthesizer = MockSpeechSynthesizer()
        let environment = TestEnvironment.make(settings: settings, synthesizer: synthesizer)
        _ = makeModel(environment: environment, questions: [TestEnvironment.integerQuestion()])
        XCTAssertTrue(synthesizer.spokenTexts.isEmpty)
    }

    func testChoosingTheCorrectAnswerGivesPositiveFeedback() {
        let environment = TestEnvironment.make()
        let question = TestEnvironment.integerQuestion(correct: 3)
        let model = makeModel(environment: environment, questions: [question])

        guard let correct = question.choices.first(where: \.isCorrect) else {
            return XCTFail("正解の選択肢がない")
        }
        model.select(choice: correct)

        XCTAssertEqual(model.stage, .feedback)
        XCTAssertEqual(model.feedback?.judgement, .correct)
        XCTAssertEqual(model.feedback?.starsEarned, 2)
        XCTAssertTrue(model.showsConfetti)
    }

    func testWrongAnswerAllowsRetryWithHint() {
        let environment = TestEnvironment.make()
        let question = TestEnvironment.integerQuestion(correct: 3)
        let model = makeModel(environment: environment, questions: [question])

        guard let wrong = question.choices.first(where: { !$0.isCorrect }) else {
            return XCTFail("誤答の選択肢がない")
        }
        model.select(choice: wrong)
        XCTAssertEqual(model.feedback?.judgement, .incorrect)
        XCTAssertTrue(model.feedback?.canRetry ?? false)

        model.retryCurrentQuestion()
        XCTAssertEqual(model.stage, .asking)
        XCTAssertTrue(model.showsHint)
        XCTAssertEqual(model.visibleChoices.count, 2, "ヒント時は選択肢を減らす")
        XCTAssertTrue(model.visibleChoices.contains(where: \.isCorrect))
    }

    func testNumberPadInput() {
        let environment = TestEnvironment.make()
        let model = makeModel(
            environment: environment,
            questions: [TestEnvironment.integerQuestion(correct: 12)]
        )
        model.answerMode = .numberPad
        model.appendDigit(1)
        model.appendDigit(2)
        XCTAssertEqual(model.numberInput, "12")
        model.submitNumberInput()
        XCTAssertEqual(model.feedback?.judgement, .correct)
    }

    func testNumberPadClear() {
        let environment = TestEnvironment.make()
        let model = makeModel(environment: environment, questions: [TestEnvironment.integerQuestion()])
        model.answerMode = .numberPad
        model.appendDigit(9)
        model.clearInput()
        XCTAssertTrue(model.numberInput.isEmpty)
    }

    func testClockTimeInputUsesTwoFields() {
        let environment = TestEnvironment.make()
        let time = ClockTime(hour: 3, minute: 30)
        let question = Question(
            skill: .clockRead,
            difficulty: .level3,
            prompt: Prompt(displayText: "なんじ？", spokenText: "なんじ かな？"),
            content: .clockRead(time: time),
            answer: .time(time, toleranceMinutes: 0),
            answerModes: [.numberPad, .choice],
            choices: []
        )
        let model = makeModel(environment: environment, questions: [question])
        model.answerMode = .numberPad

        model.appendDigit(3)
        model.activeTimeField = .minute
        model.appendDigit(3)
        model.appendDigit(0)
        XCTAssertEqual(model.hourInput, "3")
        XCTAssertEqual(model.minuteInput, "30")

        model.submitTimeInput()
        XCTAssertEqual(model.feedback?.judgement, .correct)
    }

    func testDraggedClockAnswer() {
        let environment = TestEnvironment.make()
        let target = ClockTime(hour: 7, minute: 0)
        let question = Question(
            skill: .clockSet,
            difficulty: .level1,
            prompt: Prompt(displayText: "7じに してね", spokenText: "7時に してね"),
            content: .clockSet(target: target, start: ClockTime(hour: 12, minute: 0), minuteStep: 30),
            answer: .time(target, toleranceMinutes: 0),
            answerModes: [.dragHands],
            choices: []
        )
        let model = makeModel(environment: environment, questions: [question])
        XCTAssertEqual(model.draggedTime, ClockTime(hour: 12, minute: 0), "はじめの位置がセットされる")

        model.draggedTime = target
        model.submitDraggedTime()
        XCTAssertEqual(model.feedback?.judgement, .correct)
    }

    func testTraceAnswerUsesRenderedGlyph() {
        let environment = TestEnvironment.make()
        let question = TestEnvironment.traceQuestion()
        let model = makeModel(environment: environment, questions: [question])

        model.traceStrokes = SessionViewModelTests.strokesAlongGlyph(of: question)
        model.submitTrace()

        XCTAssertEqual(model.feedback?.judgement, .correct, "お手本の上をなぞれば正解になる")
    }

    func testScribblingTheWholeCanvasIsNotCorrect() {
        let environment = TestEnvironment.make()
        let model = makeModel(environment: environment, questions: [TestEnvironment.traceQuestion()])

        // キャンバス全体を塗りつぶす。お手本は覆えるが、はみ出しだらけになる。
        var strokes: [[TracePoint]] = []
        for row in stride(from: 0.05, through: 0.95, by: 0.03) {
            strokes.append([
                TracePoint(x: 0.02, y: row),
                TracePoint(x: 0.98, y: row)
            ])
        }
        model.traceStrokes = strokes
        model.submitTrace()

        XCTAssertNotEqual(
            model.feedback?.judgement,
            .correct,
            "ぐりぐり塗りつぶしただけでは書けたことにしない"
        )
    }

    /// お手本の形に沿った線をつくる。マスクの埋まっている行だけをなぞる。
    private static func strokesAlongGlyph(of question: Question) -> [[TracePoint]] {
        let text = AnswerGrader.correctAnswerDisplay(for: question)
        let mask = GlyphMaskRenderer.mask(for: text)
        guard mask.width > 0, mask.height > 0 else { return [] }

        var points: [TracePoint] = []
        for y in 0 ..< mask.height {
            let filled = (0 ..< mask.width).filter { mask.isFilled(x: $0, y: y) }
            guard let first = filled.first, let last = filled.last else { continue }
            for x in first ... last where mask.isFilled(x: x, y: y) {
                points.append(
                    TracePoint(
                        x: (Double(x) + 0.5) / Double(mask.width),
                        y: (Double(y) + 0.5) / Double(mask.height)
                    )
                )
            }
        }
        return points.isEmpty ? [] : [points]
    }

    func testEmptyTraceIsNotCorrect() {
        let environment = TestEnvironment.make()
        let model = makeModel(environment: environment, questions: [TestEnvironment.traceQuestion()])
        model.traceStrokes = []
        model.submitTrace()
        XCTAssertEqual(model.feedback?.judgement, .incorrect)
    }

    func testAdvancingThroughAllQuestionsFinishesAndSaves() {
        let store = InMemoryLearningHistoryStore()
        let environment = TestEnvironment.make(historyStore: store)
        let questions = [
            TestEnvironment.integerQuestion(correct: 1),
            TestEnvironment.integerQuestion(correct: 2)
        ]
        let model = makeModel(environment: environment, questions: questions)

        model.submitNumberInputDirectly(1)
        model.advance()
        model.submitNumberInputDirectly(2)
        model.advance()

        XCTAssertEqual(model.stage, .finished)
        XCTAssertEqual(model.summary?.correctCount, 2)
        XCTAssertEqual(store.sessions().count, 1)
        XCTAssertEqual(store.attempts().count, 2)
        XCTAssertGreaterThan(environment.progress.totalStars, 0)
    }

    func testVoiceAnswerFlowWithScriptedRecogniser() {
        let environment = TestEnvironment.make(voiceScript: ["さん"])
        let model = makeModel(
            environment: environment,
            questions: [TestEnvironment.integerQuestion(correct: 3)]
        )
        model.answerMode = .voice
        XCTAssertTrue(model.isVoiceAvailable)

        model.startVoice()
        TestEnvironment.wait(until: { model.stage == .feedback })

        XCTAssertEqual(model.feedback?.judgement, .correct)
    }

    func testUnrecognisedSpeechDoesNotCountAsWrong() {
        let store = InMemoryLearningHistoryStore()
        let environment = TestEnvironment.make(
            voiceScript: ["わかんない"],
            historyStore: store
        )
        let model = makeModel(
            environment: environment,
            questions: [TestEnvironment.integerQuestion(correct: 3)]
        )
        model.answerMode = .voice
        model.startVoice()

        TestEnvironment.wait(until: { model.voiceState == .finished(.unclear) })
        XCTAssertEqual(model.stage, .asking, "聞き取れなかっただけなので問題は進めない")
        XCTAssertNil(model.feedback)
        XCTAssertTrue(store.attempts().isEmpty, "学習履歴にも不正解として残さない")
    }

    func testVoiceModeIsHiddenWhenTurnedOff() {
        var settings = AppSettings.default
        settings.voiceAnswerEnabled = false
        let environment = TestEnvironment.make(settings: settings)
        let model = makeModel(
            environment: environment,
            questions: [TestEnvironment.integerQuestion(correct: 3)]
        )
        XCTAssertFalse(model.availableModes.contains(.voice))
        XCTAssertFalse(model.isVoiceAvailable)
        XCTAssertFalse(model.availableModes.isEmpty, "タップ回答は必ず残る")
    }

    func testAdsAreSuppressedDuringLearning() {
        let adPresenter = MockAdPresenter(allow: true)
        let environment = TestEnvironment.make(adPresenter: adPresenter)
        let model = makeModel(environment: environment, questions: [TestEnvironment.integerQuestion()])

        XCTAssertTrue(adPresenter.isLearningSessionActive)
        XCTAssertFalse(adPresenter.shouldPresentParentAd(adsRemoved: false), "学習中は広告を出さない")

        model.submitNumberInputDirectly(3)
        model.advance()
        XCTAssertFalse(adPresenter.isLearningSessionActive)
    }

    func testClosingMidSessionStillSavesProgress() {
        let store = InMemoryLearningHistoryStore()
        let environment = TestEnvironment.make(historyStore: store)
        let model = makeModel(
            environment: environment,
            questions: [
                TestEnvironment.integerQuestion(correct: 1),
                TestEnvironment.integerQuestion(correct: 2)
            ]
        )
        model.submitNumberInputDirectly(1)
        model.close()

        XCTAssertEqual(store.attempts().count, 1)
        XCTAssertEqual(store.sessions().count, 1)
    }

    func testCountingTapsToggle() {
        let environment = TestEnvironment.make()
        let model = makeModel(environment: environment, questions: [TestEnvironment.integerQuestion(correct: 4)])
        model.toggleCounted(index: 0)
        model.toggleCounted(index: 1)
        XCTAssertEqual(model.countedIndices, [0, 1])
        model.toggleCounted(index: 0)
        XCTAssertEqual(model.countedIndices, [1])
    }
}

private extension SessionViewModel {
    /// テスト用に数字入力をまとめて行う。
    func submitNumberInputDirectly(_ value: Int) {
        answerMode = .numberPad
        clearInput()
        for character in "\(value)" {
            if let digit = character.wholeNumberValue {
                appendDigit(digit)
            }
        }
        submitNumberInput()
    }
}
