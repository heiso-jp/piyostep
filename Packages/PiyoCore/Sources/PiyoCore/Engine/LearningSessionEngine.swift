import Foundation

/// 1 問ごとのフィードバック。
public struct SessionFeedback: Equatable, Sendable {
    public let judgement: AnswerJudgement
    /// 子どもに見せる／読み上げることば
    public let message: String
    public let starsEarned: Int
    /// もう一度挑戦できるか
    public let canRetry: Bool
    /// ヒントを出すべきか
    public let showHint: Bool
    /// 答えを見せるか（挑戦回数を使い切ったとき）
    public let revealsAnswer: Bool
    public let correctAnswerDisplay: String

    public init(
        judgement: AnswerJudgement,
        message: String,
        starsEarned: Int,
        canRetry: Bool,
        showHint: Bool,
        revealsAnswer: Bool,
        correctAnswerDisplay: String
    ) {
        self.judgement = judgement
        self.message = message
        self.starsEarned = starsEarned
        self.canRetry = canRetry
        self.showHint = showHint
        self.revealsAnswer = revealsAnswer
        self.correctAnswerDisplay = correctAnswerDisplay
    }
}

/// セッションの結果。
public struct SessionSummary: Equatable, Sendable {
    public let record: SessionRecord
    public let attempts: [AttemptRecord]

    public init(record: SessionRecord, attempts: [AttemptRecord]) {
        self.record = record
        self.attempts = attempts
    }

    public var questionCount: Int { record.questionCount }
    public var correctCount: Int { record.correctCount }
    public var starsEarned: Int { record.starsEarned }

    public var accuracy: Double? {
        questionCount > 0 ? Double(correctCount) / Double(questionCount) : nil
    }

    /// 子どもに見せる、ねぎらいのことば。点数で評価しない。
    public var childMessage: String {
        switch correctCount {
        case 0: return "さいごまで やったね！ すごい！"
        default: return "よく がんばったね！"
        }
    }
}

/// セッションの進行状態。
public enum SessionPhase: Equatable, Sendable {
    case notStarted
    case asking(index: Int)
    case feedback(index: Int, SessionFeedback)
    case completed(SessionSummary)
}

/// 学習セッションの進行を司る。
public final class LearningSessionEngine {
    /// 1 問あたりの最大挑戦回数（1 回目 + 再挑戦 2 回）
    public static let maxAttemptsPerQuestion = 3

    public let kind: SessionKind
    public let subject: Subject?
    public private(set) var questions: [Question]
    public private(set) var phase: SessionPhase = .notStarted
    public private(set) var currentIndex: Int = 0
    /// 現在の問題での挑戦回数（unclear は数えない）
    public private(set) var currentAttemptCount: Int = 0
    public private(set) var attemptRecords: [AttemptRecord] = []
    public private(set) var starsEarned: Int = 0
    public private(set) var correctCount: Int = 0

    private let grader: AnswerGrader
    private let clock: ClockProviding
    private let sessionID = UUID()
    private var startedAt: Date
    private var questionStartedAt: Date
    /// 問題ごとに「正解済みか」を持つ
    private var solvedQuestionIDs: Set<UUID> = []

    public init(
        kind: SessionKind,
        subject: Subject? = nil,
        questions: [Question],
        grader: AnswerGrader = AnswerGrader(),
        clock: ClockProviding = SystemClock()
    ) {
        self.kind = kind
        self.subject = subject
        self.questions = questions
        self.grader = grader
        self.clock = clock
        self.startedAt = clock.now
        self.questionStartedAt = clock.now
    }

    public var currentQuestion: Question? {
        guard currentIndex >= 0, currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    /// 0.0 - 1.0 の進捗。
    public var progress: Double {
        guard !questions.isEmpty else { return 1 }
        return Double(currentIndex) / Double(questions.count)
    }

    public var isCompleted: Bool {
        if case .completed = phase { return true }
        return false
    }

    /// セッションを開始する。
    @discardableResult
    public func start() -> SessionPhase {
        startedAt = clock.now
        questionStartedAt = clock.now
        currentIndex = 0
        currentAttemptCount = 0
        attemptRecords = []
        starsEarned = 0
        correctCount = 0
        solvedQuestionIDs = []
        phase = questions.isEmpty ? .completed(makeSummary()) : .asking(index: 0)
        return phase
    }

    /// 回答を採点する。
    @discardableResult
    public func submit(_ input: AnswerInput) -> SessionFeedback {
        guard let question = currentQuestion else {
            return SessionFeedback(
                judgement: .unclear,
                message: "",
                starsEarned: 0,
                canRetry: false,
                showHint: false,
                revealsAnswer: false,
                correctAnswerDisplay: ""
            )
        }

        let evaluation = grader.evaluate(question: question, input: input)
        let now = clock.now
        let duration = max(0, now.timeIntervalSince(questionStartedAt))

        // unclear（聞き取れなかった）は挑戦回数にも履歴にも数えない。
        if evaluation.judgement == .unclear {
            let feedback = SessionFeedback(
                judgement: .unclear,
                message: "もういちど いってみよう！",
                starsEarned: 0,
                canRetry: true,
                showHint: currentAttemptCount >= 1,
                revealsAnswer: false,
                correctAnswerDisplay: evaluation.correctAnswerDisplay
            )
            phase = .feedback(index: currentIndex, feedback)
            return feedback
        }

        currentAttemptCount += 1
        let stars = StarRule.stars(forAttemptIndex: currentAttemptCount, judgement: evaluation.judgement)
        starsEarned += stars

        let record = AttemptRecord(
            sessionID: sessionID,
            skill: question.skill,
            difficulty: question.difficulty,
            judgement: evaluation.judgement,
            answerMode: LearningSessionEngine.answerMode(for: input, question: question),
            attemptIndex: currentAttemptCount,
            duration: duration,
            createdAt: now,
            itemID: question.itemID,
            ability: question.ability
        )
        attemptRecords.append(record)

        let outOfAttempts = currentAttemptCount >= LearningSessionEngine.maxAttemptsPerQuestion
        let isCorrect = evaluation.judgement == .correct
        if isCorrect, !solvedQuestionIDs.contains(question.id) {
            solvedQuestionIDs.insert(question.id)
            correctCount += 1
        }

        let feedback = SessionFeedback(
            judgement: evaluation.judgement,
            message: LearningSessionEngine.message(
                judgement: evaluation.judgement,
                attemptIndex: currentAttemptCount,
                outOfAttempts: outOfAttempts,
                correctAnswerDisplay: evaluation.correctAnswerDisplay
            ),
            starsEarned: stars,
            canRetry: !isCorrect && !outOfAttempts,
            showHint: !isCorrect && currentAttemptCount >= 1,
            revealsAnswer: !isCorrect && outOfAttempts,
            correctAnswerDisplay: evaluation.correctAnswerDisplay
        )
        phase = .feedback(index: currentIndex, feedback)
        return feedback
    }

    /// 同じ問題をもう一度。
    @discardableResult
    public func retry() -> SessionPhase {
        questionStartedAt = clock.now
        phase = .asking(index: currentIndex)
        return phase
    }

    /// 次の問題へ進む。最後まで行ったら完了。
    @discardableResult
    public func advance() -> SessionPhase {
        currentIndex += 1
        currentAttemptCount = 0
        questionStartedAt = clock.now
        if currentIndex >= questions.count {
            phase = .completed(makeSummary())
        } else {
            phase = .asking(index: currentIndex)
        }
        return phase
    }

    /// 途中でやめる（ホームに戻る）。それまでの結果は残す。
    @discardableResult
    public func finishEarly() -> SessionSummary {
        let summary = makeSummary()
        phase = .completed(summary)
        return summary
    }

    private func makeSummary() -> SessionSummary {
        // 参加賞：ひとつも★が付かないことはないようにする。
        let stars = max(starsEarned, questions.isEmpty ? 0 : StarRule.participationStars)
        let record = SessionRecord(
            id: sessionID,
            kind: kind,
            subject: subject,
            startedAt: startedAt,
            endedAt: clock.now,
            questionCount: questions.count,
            correctCount: correctCount,
            starsEarned: stars
        )
        return SessionSummary(record: record, attempts: attemptRecords)
    }

    // MARK: - ことば

    static func message(
        judgement: AnswerJudgement,
        attemptIndex: Int,
        outOfAttempts: Bool,
        correctAnswerDisplay: String
    ) -> String {
        switch judgement {
        case .correct:
            return attemptIndex <= 1 ? "せいかい！ すごい！" : "せいかい！ よく できたね！"
        case .unclear:
            return "もういちど いってみよう！"
        case .incorrect:
            if outOfAttempts {
                return "こたえは 「\(correctAnswerDisplay)」 だよ！ つぎ いってみよう！"
            }
            return attemptIndex <= 1 ? "おしい！ もういっかい！" : "ヒントを みて もういっかい！"
        }
    }

    static func answerMode(for input: AnswerInput, question: Question) -> AnswerMode {
        switch input {
        case .choice: return .choice
        case .integer: return .numberPad
        case .time:
            // 針を動かす問題ならドラッグ、時刻を読む問題なら数字入力。
            return question.answerModes.contains(.dragHands) ? .dragHands : .numberPad
        case .speech: return .voice
        case .trace: return .trace
        case .skipped: return .choice
        }
    }
}
