import XCTest
@testable import PiyoCore

final class ClockQuestionGeneratorTests: XCTestCase {

    func testGranularityPerLevel() {
        XCTAssertEqual(ClockGranularity.forLevel(.level1), .hourOnly)
        XCTAssertEqual(ClockGranularity.forLevel(.level2), .halfHour)
        XCTAssertEqual(ClockGranularity.forLevel(.level3), .quarterHour)
        XCTAssertEqual(ClockGranularity.forLevel(.level4), .fiveMinutes)
        XCTAssertEqual(ClockGranularity.forLevel(.level5), .oneMinute)

        XCTAssertEqual(ClockGranularity.hourOnly.allowedMinutes, [0])
        XCTAssertEqual(ClockGranularity.halfHour.allowedMinutes, [0, 30])
        XCTAssertEqual(ClockGranularity.fiveMinutes.allowedMinutes.count, 12)
        XCTAssertEqual(ClockGranularity.oneMinute.allowedMinutes.count, 60)
    }

    func testLevel1OnlyProducesWholeHours() {
        let generator = ClockReadQuestionGenerator()
        let random = Fixture.random()
        for _ in 0 ..< 60 {
            let question = generator.generate(level: .level1, random: random, allowVoice: true)
            guard case let .clockRead(time) = question.content else {
                return XCTFail("clockRead 以外が生成された")
            }
            XCTAssertEqual(time.minute, 0)
            XCTAssertTrue((1 ... 12).contains(time.hour))
        }
    }

    func testLevel2ProducesOnlyWholeOrHalfHours() {
        let generator = ClockReadQuestionGenerator()
        let random = Fixture.random(seed: 7)
        var sawHalf = false
        for _ in 0 ..< 120 {
            let question = generator.generate(level: .level2, random: random, allowVoice: true)
            guard case let .clockRead(time) = question.content else { continue }
            XCTAssertTrue([0, 30].contains(time.minute))
            if time.minute == 30 { sawHalf = true }
        }
        XCTAssertTrue(sawHalf, "Lv2 では 30 分も出題されるべき")
    }

    func testChoicesContainExactlyOneCorrectAnswer() {
        let generator = ClockReadQuestionGenerator()
        let random = Fixture.random(seed: 99)
        for level in 1 ... 5 {
            for _ in 0 ..< 20 {
                let question = generator.generate(
                    level: DifficultyLevel(level),
                    random: random,
                    allowVoice: true
                )
                XCTAssertEqual(question.choices.count, 4)
                XCTAssertEqual(question.choices.filter(\.isCorrect).count, 1)
                let labels = Set(question.choices.map(\.label))
                XCTAssertEqual(labels.count, 4, "選択肢が重複している")
            }
        }
    }

    func testCorrectChoiceMatchesExpectedAnswer() {
        let generator = ClockReadQuestionGenerator()
        let random = Fixture.random(seed: 3)
        let question = generator.generate(level: .level4, random: random, allowVoice: true)
        guard case let .time(expected, _) = question.answer,
              let correct = question.choices.first(where: \.isCorrect),
              case let .text(shown) = correct.display else {
            return XCTFail("時刻問題の構造が想定と違う")
        }
        XCTAssertEqual(shown, expected.displayJapanese)
    }

    func testVoiceModeCanBeDisabled() {
        let generator = ClockReadQuestionGenerator()
        let withVoice = generator.generate(level: .level2, random: Fixture.random(), allowVoice: true)
        let withoutVoice = generator.generate(level: .level2, random: Fixture.random(), allowVoice: false)
        XCTAssertTrue(withVoice.answerModes.contains(.voice))
        XCTAssertFalse(withoutVoice.answerModes.contains(.voice))
        XCTAssertTrue(withoutVoice.answerModes.contains(.choice))
    }

    func testClockSetProducesDistinctStartAndTarget() {
        let generator = ClockSetQuestionGenerator()
        let random = Fixture.random(seed: 11)
        for level in 1 ... 5 {
            for _ in 0 ..< 20 {
                let question = generator.generate(
                    level: DifficultyLevel(level),
                    random: random,
                    allowVoice: true
                )
                guard case let .clockSet(target, start, step) = question.content else {
                    return XCTFail("clockSet 以外が生成された")
                }
                XCTAssertNotEqual(target, start, "はじめの位置が答えと同じ")
                XCTAssertEqual(step, ClockGranularity.forLevel(DifficultyLevel(level)).dragStepMinutes)
                XCTAssertEqual(question.answerModes, [.dragHands])
            }
        }
    }

    func testClockSetToleranceOnlyAtFinestLevel() {
        let generator = ClockSetQuestionGenerator()
        let coarse = generator.generate(level: .level3, random: Fixture.random(), allowVoice: true)
        let fine = generator.generate(level: .level5, random: Fixture.random(), allowVoice: true)
        guard case let .time(_, coarseTolerance) = coarse.answer,
              case let .time(_, fineTolerance) = fine.answer else {
            return XCTFail("時刻の期待値が取れない")
        }
        XCTAssertEqual(coarseTolerance, 0)
        XCTAssertEqual(fineTolerance, 1)
    }

    func testGenerationIsDeterministicForSameSeed() {
        let generator = ClockReadQuestionGenerator()
        let first = generator.generate(level: .level4, random: Fixture.random(seed: 42), allowVoice: true)
        let second = generator.generate(level: .level4, random: Fixture.random(seed: 42), allowVoice: true)
        XCTAssertEqual(first.content, second.content)
        XCTAssertEqual(first.choices.map(\.label), second.choices.map(\.label))
    }
}

final class NumberQuestionGeneratorTests: XCTestCase {

    func testCountRangesGrowWithLevel() {
        XCTAssertEqual(CountQuestionGenerator.countRange(for: .level1), 1 ... 5)
        XCTAssertEqual(CountQuestionGenerator.countRange(for: .level5), 10 ... 30)
    }

    func testCountQuestionStaysInRange() {
        let generator = CountQuestionGenerator()
        let random = Fixture.random(seed: 5)
        for level in 1 ... 5 {
            let range = CountQuestionGenerator.countRange(for: DifficultyLevel(level))
            for _ in 0 ..< 30 {
                let question = generator.generate(
                    level: DifficultyLevel(level),
                    random: random,
                    allowVoice: true
                )
                guard case let .countObjects(_, count) = question.content else {
                    return XCTFail("countObjects 以外が生成された")
                }
                XCTAssertTrue(range.contains(count))
                XCTAssertEqual(question.answer, .integer(count))
                XCTAssertEqual(question.choices.filter(\.isCorrect).count, 1)
                XCTAssertEqual(Set(question.choices.map(\.label)).count, 4)
            }
        }
    }

    func testNumberReadRangesPerLevel() {
        XCTAssertEqual(NumberReadQuestionGenerator.valueRange(for: .level1), 0 ... 9)
        XCTAssertEqual(NumberReadQuestionGenerator.valueRange(for: .level2), 10 ... 20)
        XCTAssertEqual(NumberReadQuestionGenerator.valueRange(for: .level3), 20 ... 99)
        XCTAssertEqual(NumberReadQuestionGenerator.valueRange(for: .level4), 100 ... 199)
        XCTAssertEqual(NumberReadQuestionGenerator.valueRange(for: .level5), 100 ... 999)
    }

    func testNumberReadPrefersVoiceFirst() {
        let question = NumberReadQuestionGenerator().generate(
            level: .level2,
            random: Fixture.random(),
            allowVoice: true
        )
        XCTAssertEqual(question.answerModes.first, .voice)
    }

    func testPlaceValueNeverAskedBelowLevel3() {
        XCTAssertEqual(PlaceValueQuestionGenerator.effectiveLevel(.level1), .level3)
        XCTAssertEqual(PlaceValueQuestionGenerator.effectiveLevel(.level4), .level4)

        let question = PlaceValueQuestionGenerator().generate(
            level: .level1,
            random: Fixture.random(),
            allowVoice: true
        )
        XCTAssertEqual(question.difficulty, .level3)
    }

    func testPlaceValueAnswerMatchesDigit() {
        let generator = PlaceValueQuestionGenerator()
        let random = Fixture.random(seed: 77)
        for level in 3 ... 5 {
            for _ in 0 ..< 40 {
                let question = generator.generate(
                    level: DifficultyLevel(level),
                    random: random,
                    allowVoice: true
                )
                guard case let .placeValue(value, place) = question.content,
                      case let .integer(expected) = question.answer else {
                    return XCTFail("placeValue 以外が生成された")
                }
                XCTAssertEqual(expected, place.digit(of: value))
                XCTAssertNotEqual(expected, 0, "0 は視覚的に分かりにくいので避ける")
                if level == 3 {
                    XCTAssertNotEqual(place, .hundreds, "Lv3 では百の位は出題しない")
                }
            }
        }
    }

    func testPlaceValueBreakdown() {
        let breakdown = PlaceValueBreakdown(value: 357)
        XCTAssertEqual(breakdown.hundreds, 3)
        XCTAssertEqual(breakdown.tens, 5)
        XCTAssertEqual(breakdown.ones, 7)
        XCTAssertEqual(breakdown.total, 357)
        XCTAssertEqual(breakdown.digit(at: .tens), 5)

        let small = PlaceValueBreakdown(value: 8)
        XCTAssertEqual(small.hundreds, 0)
        XCTAssertEqual(small.tens, 0)
        XCTAssertEqual(small.ones, 8)
    }

    func testNumberPlaceDigitExtraction() {
        XCTAssertEqual(NumberPlace.ones.digit(of: 472), 2)
        XCTAssertEqual(NumberPlace.tens.digit(of: 472), 7)
        XCTAssertEqual(NumberPlace.hundreds.digit(of: 472), 4)
        XCTAssertEqual(NumberPlace.hundreds.digit(of: 72), 0)
    }
}

final class KanaAndEnglishGeneratorTests: XCTestCase {

    func testKanaCatalogHasFullGojuon() {
        XCTAssertEqual(KanaCatalog.all.count, 46)
        XCTAssertEqual(KanaCatalog.teachable.count, 44)
        XCTAssertEqual(Set(KanaCatalog.all.map(\.hiragana)).count, 46, "ひらがなが重複している")
        XCTAssertEqual(Set(KanaCatalog.all.map(\.katakana)).count, 46, "カタカナが重複している")
    }

    func testKanaExampleWordsStartWithTheirCharacter() {
        for card in KanaCatalog.teachable {
            XCTAssertTrue(
                card.hiraganaWord.hasPrefix(card.hiragana),
                "\(card.hiragana) の例語「\(card.hiraganaWord)」がその文字で始まっていない"
            )
            XCTAssertTrue(
                card.katakanaWord.hasPrefix(card.katakana),
                "\(card.katakana) の例語「\(card.katakanaWord)」がその文字で始まっていない"
            )
        }
    }

    func testKanaPoolGrowsWithLevel() {
        let easy = KanaCatalog.cards(for: .level1)
        let hard = KanaCatalog.cards(for: .level5)
        XCTAssertLessThan(easy.count, hard.count)
        XCTAssertEqual(hard.count, KanaCatalog.teachable.count)
        XCTAssertTrue(easy.allSatisfy { $0.rowIndex <= 1 })
    }

    func testHiraganaReadQuestionStructure() {
        let generator = KanaReadQuestionGenerator(subject: .hiragana)
        let question = generator.generate(level: .level2, random: Fixture.random(), allowVoice: true)
        XCTAssertEqual(question.skill, .hiraganaRead)
        XCTAssertEqual(question.choices.count, 4)
        XCTAssertEqual(question.choices.filter(\.isCorrect).count, 1)
        guard case let .kanaCard(card, task) = question.content else {
            return XCTFail("kanaCard 以外が生成された")
        }
        XCTAssertEqual(task, .read)
        guard case let .text(canonical, accepted, locale) = question.answer else {
            return XCTFail("text 以外の期待値")
        }
        XCTAssertEqual(canonical, card.hiragana)
        XCTAssertEqual(locale, .japanese)
        XCTAssertTrue(accepted.contains(card.hiraganaWord))
    }

    func testKatakanaReadUsesKatakanaLabels() {
        let generator = KanaReadQuestionGenerator(subject: .katakana)
        let question = generator.generate(level: .level3, random: Fixture.random(seed: 8), allowVoice: true)
        XCTAssertEqual(question.skill, .katakanaRead)
        guard case let .kanaCard(card, _) = question.content else {
            return XCTFail("kanaCard 以外が生成された")
        }
        XCTAssertTrue(question.choices.contains { $0.label == card.katakana })
    }

    func testWriteQuestionUsesTraceAnswer() {
        let generator = KanaWriteQuestionGenerator(subject: .hiragana)
        let trace = generator.generate(level: .level2, random: Fixture.random(), allowVoice: true)
        XCTAssertEqual(trace.answerModes, [.trace])
        guard case let .trace(required) = trace.answer else {
            return XCTFail("trace 以外の期待値")
        }
        XCTAssertEqual(required, KanaWriteQuestionGenerator.requiredCoverage(for: .level2), accuracy: 0.0001)
        XCTAssertEqual(KanaWriteQuestionGenerator.task(for: .level2), .trace)
        XCTAssertEqual(KanaWriteQuestionGenerator.task(for: .level4), .write, "Lv4 以上はお手本なし")
    }

    func testKanaWordQuestionAsksForFirstCharacter() {
        let generator = KanaWordQuestionGenerator(subject: .hiragana)
        let question = generator.generate(level: .level3, random: Fixture.random(seed: 4), allowVoice: true)
        XCTAssertEqual(question.skill, .hiraganaWord)
        guard case let .kanaWord(card, subject) = question.content else {
            return XCTFail("kanaWord 以外が生成された")
        }
        XCTAssertEqual(subject, .hiragana)
        XCTAssertTrue(question.prompt.spokenText.contains(card.hiraganaWord))
        XCTAssertTrue(question.choices.contains { $0.isCorrect && $0.label == card.hiragana })
    }

    func testKatakanaWordUsesKatakanaSkill() {
        let generator = KanaWordQuestionGenerator(subject: .katakana)
        XCTAssertEqual(generator.skill, .katakanaWord)
    }

    func testAlphabetCatalogCoversAtoZ() {
        XCTAssertEqual(AlphabetCatalog.all.count, 26)
        XCTAssertEqual(AlphabetCatalog.all.first?.uppercase, "A")
        XCTAssertEqual(AlphabetCatalog.all.last?.uppercase, "Z")
        for card in AlphabetCatalog.all {
            XCTAssertEqual(card.lowercase, card.uppercase.lowercased())
            XCTAssertNotNil(
                EnglishWordCatalog.card(for: card.exampleWordID),
                "\(card.uppercase) の例単語 \(card.exampleWordID) が見つからない"
            )
        }
    }

    func testAlphabetQuestionAcceptsLetterNames() {
        let generator = AlphabetReadQuestionGenerator()
        let question = generator.generate(level: .level1, random: Fixture.random(), allowVoice: true)
        guard case let .alphabetCard(card, task, _) = question.content,
              case let .text(canonical, accepted, locale) = question.answer else {
            return XCTFail("alphabetCard 以外が生成された")
        }
        XCTAssertEqual(task, .read)
        XCTAssertEqual(locale, .englishUS)
        XCTAssertEqual(canonical, card.uppercase.lowercased())
        XCTAssertTrue(accepted.contains(card.letterName.lowercased()))
    }

    func testAlphabetLevel1UsesUppercaseOnly() {
        let generator = AlphabetReadQuestionGenerator()
        let random = Fixture.random(seed: 21)
        for _ in 0 ..< 20 {
            let question = generator.generate(level: .level1, random: random, allowVoice: true)
            guard case let .alphabetCard(_, _, isUppercase) = question.content else { continue }
            XCTAssertTrue(isUppercase)
        }
    }

    func testEnglishWordCatalogTiers() {
        let easy = EnglishWordCatalog.cards(for: .level1)
        let hard = EnglishWordCatalog.cards(for: .level5)
        XCTAssertTrue(easy.allSatisfy { $0.tier == 1 })
        XCTAssertLessThan(easy.count, hard.count)
        XCTAssertEqual(Set(EnglishWordCatalog.all.map(\.id)).count, EnglishWordCatalog.all.count)
    }

    func testEnglishWordAcceptsArticlesAndPlurals() {
        guard let apple = EnglishWordCatalog.card(for: "apple") else {
            return XCTFail("apple が見つからない")
        }
        XCTAssertTrue(apple.acceptedSpellings.contains("apple"))
        XCTAssertTrue(apple.acceptedSpellings.contains("an apple"))
        XCTAssertTrue(apple.acceptedSpellings.contains("apples"))
    }

    func testEnglishWordQuestionFallsBackToChoiceWithoutVoice() {
        let generator = EnglishWordQuestionGenerator()
        let question = generator.generate(level: .level5, random: Fixture.random(), allowVoice: false)
        XCTAssertFalse(question.answerModes.contains(.voice))
        XCTAssertTrue(question.answerModes.contains(.choice))
        guard case let .englishWord(_, task) = question.content else {
            return XCTFail("englishWord 以外が生成された")
        }
        XCTAssertEqual(task, .wordToPicture, "音声が使えないときは選ぶ形式にする")
    }
}

final class QuestionFactoryTests: XCTestCase {

    func testFactoryCoversEverySkill() {
        let factory = QuestionFactory()
        XCTAssertEqual(Set(factory.supportedSkills), Set(Skill.allCases))
    }

    func testFactoryProducesQuestionForEachSkill() {
        let factory = QuestionFactory()
        let random = Fixture.random(seed: 1234)
        for skill in Skill.allCases {
            for level in 1 ... 5 {
                let question = factory.makeQuestion(
                    skill: skill,
                    level: DifficultyLevel(level),
                    random: random,
                    allowVoice: true
                )
                XCTAssertNotNil(question, "\(skill) Lv\(level) が生成できない")
                XCTAssertEqual(question?.skill, skill)
                XCTAssertFalse(question?.answerModes.isEmpty ?? true, "\(skill) に回答方法がない")
                XCTAssertFalse(question?.prompt.spokenText.isEmpty ?? true, "\(skill) に読み上げ文がない")
            }
        }
    }

    func testWritingSkillsNeverOfferVoice() {
        let factory = QuestionFactory()
        for skill in [Skill.hiraganaWrite, .katakanaWrite, .alphabetWrite] {
            let question = factory.makeQuestion(
                skill: skill,
                level: .level2,
                random: Fixture.random(),
                allowVoice: true
            )
            XCTAssertFalse(question?.answerModes.contains(.voice) ?? true)
        }
    }
}
