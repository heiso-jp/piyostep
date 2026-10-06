import Foundation

/// 出題 1 問。
public struct Question: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let skill: Skill
    public let difficulty: DifficultyLevel
    public let prompt: Prompt
    public let content: QuestionContent
    public let answer: ExpectedAnswer
    public let answerModes: [AnswerMode]
    public let choices: [AnswerChoice]
    /// どの文字・数字を扱う問題か。項目ごとの習熟度に使う。該当しなければ nil。
    public let itemID: LearningItemID?
    /// この問題で測れる力。習熟度に算入しない練習（なぞり書きなど）では nil。
    public let ability: LearningAbility?
    /// お手本の画数。書きの評価に使う。分からなければ nil。
    public let expectedStrokeCount: Int?

    public var subject: Subject { skill.subject }

    public init(
        id: UUID = UUID(),
        skill: Skill,
        difficulty: DifficultyLevel,
        prompt: Prompt,
        content: QuestionContent,
        answer: ExpectedAnswer,
        answerModes: [AnswerMode],
        choices: [AnswerChoice] = [],
        itemID: LearningItemID? = nil,
        ability: LearningAbility? = nil,
        expectedStrokeCount: Int? = nil
    ) {
        self.id = id
        self.skill = skill
        self.difficulty = difficulty
        self.prompt = prompt
        self.content = content
        self.answer = answer
        self.answerModes = answerModes
        self.choices = choices
        self.itemID = itemID
        self.ability = ability
        self.expectedStrokeCount = expectedStrokeCount
    }

    /// 音声回答が使えるか（設定で OFF の場合は呼び出し側で除外する）。
    public var supportsVoice: Bool { answerModes.contains(.voice) }

    /// ヒント表示時に選択肢を絞り込む（正解を必ず含む）。
    public func narrowedChoices(to count: Int) -> [AnswerChoice] {
        guard choices.count > count, count > 0 else { return choices }
        var result: [AnswerChoice] = []
        if let correct = choices.first(where: { $0.isCorrect }) {
            result.append(correct)
        }
        for choice in choices where !choice.isCorrect {
            if result.count >= count { break }
            result.append(choice)
        }
        return result.sorted { lhs, rhs in
            let lhsIndex = choices.firstIndex(of: lhs) ?? 0
            let rhsIndex = choices.firstIndex(of: rhs) ?? 0
            return lhsIndex < rhsIndex
        }
    }
}

/// 子どもへの問いかけ。
public struct Prompt: Equatable, Sendable {
    /// 画面に出す短い文字列（読めない子もいるので装飾的）。
    public let displayText: String
    /// 読み上げるテキスト。
    public let spokenText: String
    /// 2 回目の挑戦で出すヒント。
    public let hintText: String?

    public init(displayText: String, spokenText: String, hintText: String? = nil) {
        self.displayText = displayText
        self.spokenText = spokenText
        self.hintText = hintText
    }
}

/// 出題内容。View はこれを見て描画を切り替える。
public enum QuestionContent: Equatable, Sendable {
    /// アナログ時計を見せて「なんじかな？」
    case clockRead(time: ClockTime)
    /// 指定時刻に針を合わせる。`minuteStep` は許容する分の刻み。
    case clockSet(target: ClockTime, start: ClockTime, minuteStep: Int)
    /// もの を数える
    case countObjects(kind: CountableObject, count: Int)
    /// 数字を読む
    case numberRead(value: Int)
    /// 位の問題
    case placeValue(value: Int, place: NumberPlace)
    /// かな 1 文字（読み / なぞり / 書き）
    case kanaCard(card: KanaCard, task: CharacterTask)
    /// かな と ことば の対応（表示する表記系も持つ）
    case kanaWord(card: KanaCard, subject: Subject)
    /// アルファベット
    case alphabetCard(card: AlphabetCard, task: CharacterTask, isUppercase: Bool)
    /// 英単語
    case englishWord(card: EnglishWordCard, task: EnglishWordTask)
}

/// 文字系の課題種別。
public enum CharacterTask: String, Equatable, Sendable, Codable {
    case read    // 読む（選択 or 音声）
    case trace   // なぞる
    case write   // 自由書き
}

/// 英単語の課題種別。
public enum EnglishWordTask: String, Equatable, Sendable, Codable {
    case pictureToWord  // 絵 → 単語を選ぶ／言う
    case wordToPicture  // 単語 → 絵を選ぶ
    case speakWord      // 単語を発音する
}

/// 位。
public enum NumberPlace: String, CaseIterable, Equatable, Sendable, Codable {
    case ones
    case tens
    case hundreds

    public var childTitle: String {
        switch self {
        case .ones: return "いちのくらい"
        case .tens: return "じゅうのくらい"
        case .hundreds: return "ひゃくのくらい"
        }
    }

    public var multiplier: Int {
        switch self {
        case .ones: return 1
        case .tens: return 10
        case .hundreds: return 100
        }
    }

    /// `value` におけるこの位の数字。
    public func digit(of value: Int) -> Int {
        (abs(value) / multiplier) % 10
    }
}

/// 数える対象。イラストはアプリ側でコード描画する。
public enum CountableObject: String, CaseIterable, Equatable, Sendable, Codable {
    case apple
    case star
    case fish
    case ball
    case candy
    case flower
    case car
    case bear

    public var childName: String {
        switch self {
        case .apple: return "りんご"
        case .star: return "ほし"
        case .fish: return "さかな"
        case .ball: return "ボール"
        case .candy: return "あめ"
        case .flower: return "おはな"
        case .car: return "くるま"
        case .bear: return "くま"
        }
    }
}

/// 期待する正解。
public enum ExpectedAnswer: Equatable, Sendable {
    case time(ClockTime, toleranceMinutes: Int)
    case integer(Int)
    /// 文字列回答。`canonical` が正規化済みの正解、`accepted` は追加で許す表記。
    case text(canonical: String, accepted: [String], locale: RecognitionLocale)
    /// なぞり書き。`requiredCoverage` 以上なぞれば正解。
    case trace(requiredCoverage: Double)
}

/// 回答手段。
public enum AnswerMode: String, CaseIterable, Equatable, Sendable, Codable {
    case choice      // 選択肢タップ
    case numberPad   // 数字入力
    case voice       // 音声
    case dragHands   // 時計の針ドラッグ
    case trace       // なぞり書き

    public var childTitle: String {
        switch self {
        case .choice: return "えらぶ"
        case .numberPad: return "すうじ"
        case .voice: return "こえ"
        case .dragHands: return "うごかす"
        case .trace: return "なぞる"
        }
    }
}

/// 選択肢 1 つ。
public struct AnswerChoice: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// 画面に出す文字（読めない子向けに `display` も併用）
    public let label: String
    /// 読み上げるテキスト
    public let spokenText: String
    /// 描画のためのメタデータ
    public let display: ChoiceDisplay
    public let isCorrect: Bool

    public init(
        id: UUID = UUID(),
        label: String,
        spokenText: String,
        display: ChoiceDisplay,
        isCorrect: Bool
    ) {
        self.id = id
        self.label = label
        self.spokenText = spokenText
        self.display = display
        self.isCorrect = isCorrect
    }
}

/// 選択肢の見た目。
public enum ChoiceDisplay: Equatable, Sendable {
    case text(String)
    case number(Int)
    case clock(ClockTime)
    case object(CountableObject, count: Int)
    case picture(EnglishWordCard)
    case kanaWord(KanaCard, subject: Subject)
}

/// 子どもからの回答入力。
public enum AnswerInput: Equatable, Sendable {
    case choice(id: UUID)
    case integer(Int)
    case time(ClockTime)
    case speech(transcript: String, confidence: Double)
    case trace(coverage: Double)
    /// 回答を諦めた（スキップ）。不正解として扱うがネガティブ表現はしない。
    case skipped
}

/// 判定結果。
public enum AnswerJudgement: String, Equatable, Sendable, Codable {
    case correct
    case incorrect
    /// 音声が聞き取れなかった。学習上の不正解としては扱わない。
    case unclear

    /// 習熟度・正答率の集計対象に含めるか。
    public var countsTowardMastery: Bool { self != .unclear }
    public var isCorrect: Bool { self == .correct }
}

/// 判定の詳細。
public struct AnswerEvaluation: Equatable, Sendable {
    public let judgement: AnswerJudgement
    /// 正規化後の入力（音声のデバッグや保護者画面表示に使う）
    public let normalizedInput: String?
    /// 子どもに見せる正解表現
    public let correctAnswerDisplay: String

    public init(judgement: AnswerJudgement, normalizedInput: String?, correctAnswerDisplay: String) {
        self.judgement = judgement
        self.normalizedInput = normalizedInput
        self.correctAnswerDisplay = correctAnswerDisplay
    }
}
