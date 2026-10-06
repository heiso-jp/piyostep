import Foundation

/// 時計の難易度ごとの分の刻み。
public enum ClockGranularity: Int, CaseIterable, Sendable {
    case hourOnly = 0        // ○時ちょうど
    case halfHour = 1        // ○時 / ○時30分
    case quarterHour = 2     // 15分刻み
    case fiveMinutes = 3     // 5分刻み
    case oneMinute = 4       // 1分刻み

    public static func forLevel(_ level: DifficultyLevel) -> ClockGranularity {
        switch level.raw {
        case 1: return .hourOnly
        case 2: return .halfHour
        case 3: return .quarterHour
        case 4: return .fiveMinutes
        default: return .oneMinute
        }
    }

    /// この粒度で許される分の一覧。
    public var allowedMinutes: [Int] {
        switch self {
        case .hourOnly: return [0]
        case .halfHour: return [0, 30]
        case .quarterHour: return [0, 15, 30, 45]
        case .fiveMinutes: return stride(from: 0, to: 60, by: 5).map { $0 }
        case .oneMinute: return Array(0 ..< 60)
        }
    }

    /// 針をドラッグするときのスナップ幅（分）。
    public var dragStepMinutes: Int {
        switch self {
        case .hourOnly: return 30
        case .halfHour: return 30
        case .quarterHour: return 15
        case .fiveMinutes: return 5
        case .oneMinute: return 1
        }
    }

    /// 針を合わせるときの許容誤差（分）。
    public var toleranceMinutes: Int {
        self == .oneMinute ? 1 : 0
    }

    public var childTitle: String {
        switch self {
        case .hourOnly: return "○じ"
        case .halfHour: return "○じ30ぷん"
        case .quarterHour: return "15ふんきざみ"
        case .fiveMinutes: return "5ふんきざみ"
        case .oneMinute: return "1ぷんきざみ"
        }
    }
}

/// 「なんじかな？」（時刻を読む）の問題生成。
public struct ClockReadQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .clockRead

    public init() {}

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let granularity = ClockGranularity.forLevel(level)
        let time = ClockReadQuestionGenerator.randomTime(granularity: granularity, random: random)
        let choices = ClockReadQuestionGenerator.makeChoices(
            correct: time,
            granularity: granularity,
            random: random
        )
        let prompt = Prompt(
            displayText: "なんじかな？",
            spokenText: "なんじかな？",
            hintText: "みじかい はりを みてね"
        )
        return Question(
            skill: skill,
            difficulty: level,
            prompt: prompt,
            content: .clockRead(time: time),
            answer: .time(time, toleranceMinutes: 0),
            answerModes: answerModes([.choice, .numberPad, .voice], allowVoice: allowVoice),
            choices: choices
        )
    }

    static func randomTime(granularity: ClockGranularity, random: RandomSource) -> ClockTime {
        let hour = random.nextInt(in: 1 ... 12)
        let minutes = granularity.allowedMinutes
        let minute = random.pick(minutes) ?? 0
        return ClockTime(hour: hour, minute: minute)
    }

    /// 「おしい！」と思える距離感の誤答を混ぜる。
    static func makeChoices(
        correct: ClockTime,
        granularity: ClockGranularity,
        random: RandomSource
    ) -> [AnswerChoice] {
        var candidates: [ClockTime] = []

        // 時だけ違う
        candidates.append(ClockTime(hour: correct.hour + 1, minute: correct.minute))
        candidates.append(ClockTime(hour: correct.hour - 1, minute: correct.minute))
        // 分だけ違う（粒度が許す範囲で）
        let otherMinutes = granularity.allowedMinutes.filter { $0 != correct.minute }
        if let minuteA = random.pick(otherMinutes) {
            candidates.append(ClockTime(hour: correct.hour, minute: minuteA))
        }
        if let minuteB = random.pick(otherMinutes) {
            candidates.append(ClockTime(hour: correct.hour + 2, minute: minuteB))
        }
        candidates.append(ClockTime(hour: correct.hour + 3, minute: correct.minute))

        var values: [ClockTime] = [correct]
        for candidate in random.shuffled(candidates) where values.count < 4 {
            if !values.contains(candidate) { values.append(candidate) }
        }
        var safety = 0
        while values.count < 4 && safety < 100 {
            safety += 1
            let candidate = randomTime(granularity: granularity, random: random)
            if !values.contains(candidate) { values.append(candidate) }
        }

        return random.shuffled(values).map { time in
            AnswerChoice(
                label: time.displayJapanese,
                spokenText: time.spokenJapanese,
                // 選択肢を時計の絵にすると、絵合わせで解けてしまい時刻を読む練習にならない。
                // 文字で出して、出題の時計を読んでから選ばせる。
                display: .text(time.displayJapanese),
                isCorrect: time == correct
            )
        }
    }
}

/// 「3じ30ぷんに してね」（針を動かす）の問題生成。
public struct ClockSetQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .clockSet

    public init() {}

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let granularity = ClockGranularity.forLevel(level)
        let target = ClockReadQuestionGenerator.randomTime(granularity: granularity, random: random)
        var start = ClockReadQuestionGenerator.randomTime(granularity: granularity, random: random)
        // 初期位置が答えと同じにならないようにする。
        var safety = 0
        while start == target && safety < 50 {
            safety += 1
            start = ClockReadQuestionGenerator.randomTime(granularity: granularity, random: random)
        }
        if start == target {
            start = ClockTime.fromTotalMinutes(target.totalMinutes + 185)
        }

        let prompt = Prompt(
            displayText: "\(target.displayJapanese)に してね",
            spokenText: "\(target.spokenJapanese)に してね",
            hintText: "ながい はりを うごかしてみよう"
        )
        return Question(
            skill: skill,
            difficulty: level,
            prompt: prompt,
            content: .clockSet(target: target, start: start, minuteStep: granularity.dragStepMinutes),
            answer: .time(target, toleranceMinutes: granularity.toleranceMinutes),
            answerModes: [.dragHands],
            choices: []
        )
    }
}
