import Foundation

/// 「いくつかな？」（数量と数字の対応）
public struct CountQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .numberCount

    public init() {}

    /// 難易度ごとに数える数の範囲。
    public static func countRange(for level: DifficultyLevel) -> ClosedRange<Int> {
        switch level.raw {
        case 1: return 1 ... 5
        case 2: return 1 ... 10
        case 3: return 5 ... 15
        case 4: return 10 ... 20
        default: return 10 ... 30
        }
    }

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let range = CountQuestionGenerator.countRange(for: level)
        let count = random.nextInt(in: range)
        let kind = random.pick(CountableObject.allCases) ?? .apple

        let choiceRange = max(1, range.lowerBound - 2) ... (range.upperBound + 3)
        let choices = ChoiceBuilder.integerChoices(
            correct: count,
            count: 4,
            range: choiceRange,
            random: random,
            spokenText: { "\($0)" },
            display: { .number($0) }
        )

        let prompt = Prompt(
            displayText: "\(kind.childName)は いくつ？",
            spokenText: "\(kind.childName)は いくつ かな？",
            hintText: "ひとつずつ さわって かぞえてみよう"
        )
        return Question(
            skill: skill,
            difficulty: level,
            prompt: prompt,
            content: .countObjects(kind: kind, count: count),
            answer: .integer(count),
            answerModes: answerModes([.choice, .numberPad, .voice], allowVoice: allowVoice),
            choices: choices,
            // 項目別に追うのは 0〜9 だけ。それ以上は Skill 単位の習熟度で見る。
            itemID: (0 ... 9).contains(count) ? .number(count) : nil,
            ability: (0 ... 9).contains(count) ? .read : nil
        )
    }
}

/// 「この すうじは なにかな？」（数字を読む）
/// 文字が読めない子でも答えられるよう、選択肢は「もの の かず」で示す。
public struct NumberReadQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .numberRead

    public init() {}

    public static func valueRange(for level: DifficultyLevel) -> ClosedRange<Int> {
        switch level.raw {
        case 1: return 0 ... 9
        case 2: return 10 ... 20
        case 3: return 20 ... 99
        case 4: return 100 ... 199
        default: return 100 ... 999
        }
    }

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let range = NumberReadQuestionGenerator.valueRange(for: level)
        let value = random.nextInt(in: range)
        let kind = random.pick(CountableObject.allCases) ?? .star

        // 選択肢は「かず」で提示する。大きな数はイラストにできないので数字表示に切り替える。
        let useObjects = value <= 10
        let choiceRange = max(0, range.lowerBound - 3) ... (range.upperBound + 3)
        let choices = ChoiceBuilder.integerChoices(
            correct: value,
            count: 4,
            range: choiceRange,
            random: random,
            spokenText: { "\($0)" },
            display: { useObjects ? .object(kind, count: $0) : .number($0) }
        )

        let prompt = Prompt(
            displayText: "なんて よむ？",
            spokenText: "この すうじ、なんて よむ かな？",
            hintText: "こえで いってみよう"
        )
        return Question(
            skill: skill,
            difficulty: level,
            prompt: prompt,
            content: .numberRead(value: value),
            answer: .integer(value),
            answerModes: answerModes([.voice, .choice, .numberPad], allowVoice: allowVoice),
            choices: choices,
            itemID: (0 ... 9).contains(value) ? .number(value) : nil,
            ability: (0 ... 9).contains(value) ? .read : nil
        )
    }
}

/// 位（一の位・十の位・百の位）
public struct PlaceValueQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .placeValue

    public init() {}

    /// この Skill は Lv3 未満では出題しない。
    public static func effectiveLevel(_ level: DifficultyLevel) -> DifficultyLevel {
        DifficultyLevel(max(level.raw, 3))
    }

    public static func valueRange(for level: DifficultyLevel) -> ClosedRange<Int> {
        switch effectiveLevel(level).raw {
        case 3: return 11 ... 99
        case 4: return 100 ... 599
        default: return 100 ... 999
        }
    }

    public static func places(for level: DifficultyLevel) -> [NumberPlace] {
        switch effectiveLevel(level).raw {
        case 3: return [.ones, .tens]
        default: return [.ones, .tens, .hundreds]
        }
    }

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let effective = PlaceValueQuestionGenerator.effectiveLevel(level)
        let range = PlaceValueQuestionGenerator.valueRange(for: effective)
        var value = random.nextInt(in: range)
        let place = random.pick(PlaceValueQuestionGenerator.places(for: effective)) ?? .ones
        // 0 が答えだと視覚的に分かりにくいので避ける。
        var safety = 0
        while place.digit(of: value) == 0 && safety < 50 {
            safety += 1
            value = random.nextInt(in: range)
        }
        let digit = place.digit(of: value)

        let choices = ChoiceBuilder.integerChoices(
            correct: digit,
            count: 4,
            range: 0 ... 9,
            random: random,
            spokenText: { "\($0)" },
            display: { .number($0) }
        )

        let prompt = Prompt(
            displayText: "\(value)の \(place.childTitle)は？",
            spokenText: "\(value)の \(place.childTitle)は いくつ かな？",
            hintText: "ブロックの かたまりを みてね"
        )
        return Question(
            skill: skill,
            difficulty: effective,
            prompt: prompt,
            content: .placeValue(value: value, place: place),
            answer: .integer(digit),
            answerModes: answerModes([.choice, .numberPad, .voice], allowVoice: allowVoice),
            choices: choices
        )
    }
}

/// 位の視覚表現（ブロック）に使う分解結果。
public struct PlaceValueBreakdown: Equatable, Sendable {
    public let hundreds: Int
    public let tens: Int
    public let ones: Int

    public init(value: Int) {
        let absolute = abs(value)
        self.hundreds = (absolute / 100) % 10
        self.tens = (absolute / 10) % 10
        self.ones = absolute % 10
    }

    public func digit(at place: NumberPlace) -> Int {
        switch place {
        case .ones: return ones
        case .tens: return tens
        case .hundreds: return hundreds
        }
    }

    /// 100 の箱・10 の棒・1 のつぶ の個数。
    public var blockCounts: (hundreds: Int, tens: Int, ones: Int) {
        (hundreds, tens, ones)
    }

    /// 合計値（分解が正しいことの検証に使う）。
    public var total: Int {
        hundreds * 100 + tens * 10 + ones
    }
}
