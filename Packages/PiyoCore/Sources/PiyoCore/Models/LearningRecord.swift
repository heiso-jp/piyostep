import Foundation

/// 1 回の回答記録。
public struct AttemptRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let sessionID: UUID?
    public let skill: Skill
    public let difficulty: DifficultyLevel
    public let judgement: AnswerJudgement
    public let answerMode: AnswerMode
    /// 何回目の挑戦か（1 始まり）
    public let attemptIndex: Int
    /// 回答に要した秒数
    public let duration: TimeInterval
    public let createdAt: Date
    /// どの文字・数字だったか。項目ごとの習熟度に使う。
    public let itemID: LearningItemID?
    /// 測れる力（よみ / かき）。習熟度に算入しない練習では nil。
    public let ability: LearningAbility?

    public init(
        id: UUID = UUID(),
        sessionID: UUID? = nil,
        skill: Skill,
        difficulty: DifficultyLevel,
        judgement: AnswerJudgement,
        answerMode: AnswerMode,
        attemptIndex: Int = 1,
        duration: TimeInterval = 0,
        createdAt: Date = Date(),
        itemID: LearningItemID? = nil,
        ability: LearningAbility? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.skill = skill
        self.difficulty = difficulty
        self.judgement = judgement
        self.answerMode = answerMode
        self.attemptIndex = attemptIndex
        self.duration = duration
        self.createdAt = createdAt
        self.itemID = itemID
        self.ability = ability
    }
}

/// 学習セッションの種類。
public enum SessionKind: String, Codable, Sendable {
    case dailyChallenge
    case freePlay
    case mealTimer
}

/// 1 セッションの記録。
public struct SessionRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let kind: SessionKind
    /// freePlay のときの教科
    public let subject: Subject?
    public let startedAt: Date
    public var endedAt: Date
    public var questionCount: Int
    public var correctCount: Int
    public var starsEarned: Int

    public init(
        id: UUID = UUID(),
        kind: SessionKind,
        subject: Subject? = nil,
        startedAt: Date,
        endedAt: Date,
        questionCount: Int = 0,
        correctCount: Int = 0,
        starsEarned: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.questionCount = questionCount
        self.correctCount = correctCount
        self.starsEarned = starsEarned
    }

    public var duration: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }
}

/// ご飯タイマー 1 回の記録。
public struct MealSessionRecord: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let characterID: String
    public let targetDuration: TimeInterval
    public let actualDuration: TimeInterval
    public let childFinishedFirst: Bool
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        characterID: String,
        targetDuration: TimeInterval,
        actualDuration: TimeInterval,
        childFinishedFirst: Bool,
        startedAt: Date
    ) {
        self.id = id
        self.characterID = characterID
        self.targetDuration = targetDuration
        self.actualDuration = actualDuration
        self.childFinishedFirst = childFinishedFirst
        self.startedAt = startedAt
    }
}

/// Skill ごとの習熟度スナップショット。
public struct MasterySnapshot: Hashable, Codable, Sendable {
    public let skill: Skill
    /// 指数移動平均による正答傾向（0.0 - 1.0）
    public var ewma: Double
    /// 集計対象になった回答数（unclear は含まない）
    public var attempts: Int
    public var correctCount: Int
    /// 現在の出題難易度
    public var level: DifficultyLevel
    /// 現在の難易度での回答数（レベル変更時にリセット）
    public var attemptsAtCurrentLevel: Int
    public var lastPracticedAt: Date?

    public static let initialEWMA: Double = 0.5

    public init(
        skill: Skill,
        ewma: Double = MasterySnapshot.initialEWMA,
        attempts: Int = 0,
        correctCount: Int = 0,
        level: DifficultyLevel = .level1,
        attemptsAtCurrentLevel: Int = 0,
        lastPracticedAt: Date? = nil
    ) {
        self.skill = skill
        self.ewma = ewma
        self.attempts = attempts
        self.correctCount = correctCount
        self.level = level
        self.attemptsAtCurrentLevel = attemptsAtCurrentLevel
        self.lastPracticedAt = lastPracticedAt
    }

    /// 通算正答率。未回答なら nil。
    public var accuracy: Double? {
        attempts > 0 ? Double(correctCount) / Double(attempts) : nil
    }

    /// 0.0 - 1.0 の習熟スコア。難易度も加味する。
    public var masteryScore: Double {
        guard attempts > 0 else { return 0 }
        let levelFactor = Double(level.raw - 1) / Double(DifficultyLevel.maximumRaw - 1)
        // 出題難易度が高いほど、同じ ewma でも習熟しているとみなす。
        let score = ewma * (0.65 + 0.35 * levelFactor)
        // 試行が少ないうちはスコアを控えめにする。
        let confidence = min(1.0, Double(attempts) / 10.0)
        return min(1.0, max(0.0, score * confidence))
    }
}
