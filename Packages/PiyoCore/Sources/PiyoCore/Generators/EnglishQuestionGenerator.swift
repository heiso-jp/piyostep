import Foundation

/// アルファベットの「読み」
public struct AlphabetReadQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .alphabetRead

    public init() {}

    /// Lv3 以上では小文字も出題する。
    public static func usesUppercase(for level: DifficultyLevel, random: RandomSource) -> Bool {
        level.raw <= 2 ? true : random.nextInt(upperBound: 2) == 0
    }

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let pool = AlphabetCatalog.cards(for: level)
        let card = random.pick(pool) ?? AlphabetCatalog.all[0]
        let isUppercase = AlphabetReadQuestionGenerator.usesUppercase(for: level, random: random)

        let choices = ChoiceBuilder.choices(
            correct: card,
            pool: pool,
            count: 4,
            random: random,
            label: { $0.character(isUppercase: isUppercase) },
            spokenText: { $0.letterName },
            display: { .text($0.character(isUppercase: isUppercase)) }
        )

        let prompt = Prompt(
            displayText: "どれかな？",
            spokenText: "\(card.letterName). どれ かな？",
            hintText: "\(card.katakanaName) だよ"
        )
        return Question(
            skill: skill,
            difficulty: level,
            prompt: prompt,
            content: .alphabetCard(card: card, task: .read, isUppercase: isUppercase),
            answer: .text(
                canonical: card.uppercase.lowercased(),
                accepted: card.acceptedSpokenForms,
                locale: .englishUS
            ),
            answerModes: answerModes([.choice, .voice], allowVoice: allowVoice),
            choices: choices,
            itemID: .alphabet(card.uppercase),
            ability: .read
        )
    }
}

/// アルファベットの「なぞり書き / 自由書き」
public struct AlphabetWriteQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .alphabetWrite

    public init() {}

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let pool = AlphabetCatalog.cards(for: level)
        let card = random.pick(pool) ?? AlphabetCatalog.all[0]
        let isUppercase = level.raw <= 3 ? true : random.nextInt(upperBound: 2) == 0
        let task = KanaWriteQuestionGenerator.task(for: level)
        let character = card.character(isUppercase: isUppercase)

        let prompt = Prompt(
            displayText: task == .trace ? "なぞってみよう" : "かいてみよう",
            spokenText: "\(card.letterName) を なぞってみよう",
            hintText: "うすい もじの うえを なぞってね"
        )
        return Question(
            skill: skill,
            difficulty: level,
            prompt: prompt,
            content: .alphabetCard(card: card, task: task, isUppercase: isUppercase),
            answer: .trace(requiredCoverage: KanaWriteQuestionGenerator.requiredCoverage(for: level)),
            answerModes: [.trace],
            choices: [
                AnswerChoice(
                    label: character,
                    spokenText: card.letterName,
                    display: .text(character),
                    isCorrect: true
                )
            ],
            // なぞりは習熟度に算入せず、自由書き（Lv4 以上）だけを「かき」として数える。
            itemID: .alphabet(card.uppercase),
            ability: task == .write ? .write : nil,
            expectedStrokeCount: StrokeCounts.count(for: card.uppercase)
        )
    }
}

/// 超基本英単語
public struct EnglishWordQuestionGenerator: QuestionGenerating {
    public let skill: Skill = .englishWordRead

    public init() {}

    /// 難易度に応じた出題形式。
    public static func task(for level: DifficultyLevel, allowVoice: Bool, random: RandomSource) -> EnglishWordTask {
        guard allowVoice else { return .wordToPicture }
        switch level.raw {
        case 1, 2:
            return .wordToPicture
        case 3:
            return random.nextInt(upperBound: 2) == 0 ? .wordToPicture : .speakWord
        default:
            return random.nextInt(upperBound: 3) == 0 ? .wordToPicture : .speakWord
        }
    }

    public func generate(level: DifficultyLevel, random: RandomSource, allowVoice: Bool) -> Question {
        let pool = EnglishWordCatalog.cards(for: level)
        let card = random.pick(pool) ?? EnglishWordCatalog.all[0]
        let task = EnglishWordQuestionGenerator.task(for: level, allowVoice: allowVoice, random: random)

        let choices = ChoiceBuilder.choices(
            correct: card,
            pool: pool,
            count: 4,
            random: random,
            label: { $0.english },
            spokenText: { $0.english },
            display: { .picture($0) }
        )

        let prompt: Prompt
        switch task {
        case .speakWord:
            prompt = Prompt(
                displayText: "えいごで いってみよう",
                spokenText: "これを えいごで いってみよう",
                hintText: "\(card.katakana) だよ"
            )
        case .wordToPicture, .pictureToWord:
            prompt = Prompt(
                displayText: "どれかな？",
                spokenText: "\(card.english). どれ かな？",
                hintText: "\(card.japanese) の ことだよ"
            )
        }

        var modes: [AnswerMode] = task == .speakWord ? [.voice, .choice] : [.choice, .voice]
        if !allowVoice { modes = modes.filter { $0 != .voice } }

        return Question(
            skill: skill,
            difficulty: level,
            prompt: prompt,
            content: .englishWord(card: card, task: task),
            answer: .text(
                canonical: card.english,
                accepted: card.acceptedSpellings,
                locale: .englishUS
            ),
            answerModes: modes,
            choices: choices
        )
    }
}
