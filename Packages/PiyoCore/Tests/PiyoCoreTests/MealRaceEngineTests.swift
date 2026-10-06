import XCTest
@testable import PiyoCore

final class MealRaceEngineTests: XCTestCase {

    private func engine(
        minutes: Int = 15,
        characterID: String = "kuma",
        seed: UInt64 = 2024
    ) -> MealRaceEngine {
        MealRaceEngine(
            configuration: MealRaceConfiguration(
                targetDuration: TimeInterval(minutes * 60),
                characterID: characterID,
                seed: seed
            )
        )
    }

    // MARK: - ペース計画

    func testPlanProgressSumsToOne() {
        for seed in UInt64(1) ... 20 {
            let plan = engine(seed: seed).plan
            XCTAssertEqual(plan.totalProgress, 1.0, accuracy: 0.0001, "seed \(seed)")
        }
    }

    func testPlanDurationMatchesFinishTime() {
        for seed in UInt64(1) ... 20 {
            let plan = engine(seed: seed).plan
            XCTAssertEqual(plan.totalDuration, plan.finishTime, accuracy: 0.5, "seed \(seed)")
        }
    }

    func testCharacterDoesNotEatAtAConstantRate() {
        let plan = engine(characterID: "nyan", seed: 5).plan
        let eatingSegments = plan.segments.filter { $0.activity == .eating }
        XCTAssertGreaterThan(eatingSegments.count, 2)
        let deltas = Set(eatingSegments.map { (($0.progressDelta) * 1000).rounded() })
        XCTAssertGreaterThan(deltas.count, 1, "一定速度ではなく変化をつける")
    }

    func testPlanIncludesRestsOrCheers() {
        let plan = engine(seed: 3).plan
        let pauses = plan.segments.filter { $0.activity == .resting || $0.activity == .cheering }
        XCTAssertFalse(pauses.isEmpty, "ひと休みや応援の時間がある")
        XCTAssertTrue(pauses.allSatisfy { $0.progressDelta == 0 })
    }

    func testRestsLastAboutAMinute() {
        var sawRest = false
        for seed in UInt64(1) ... 30 {
            let plan = MealRaceEngine.makePlan(targetDuration: 600, personality: .steady, seed: seed)
            for segment in plan.segments where segment.activity == .resting {
                sawRest = true
                XCTAssertGreaterThanOrEqual(segment.duration, 50, "寝たら 1 分くらい寝る")
                XCTAssertLessThanOrEqual(segment.duration, 70)
            }
            let breaks = plan.segments.filter { $0.activity != .eating }.reduce(0) { $0 + $1.duration }
            XCTAssertLessThanOrEqual(breaks, plan.finishTime * 0.35 + 0.001)
        }
        XCTAssertTrue(sawRest)
    }

    func testProgressIsMonotonicAndBounded() {
        let raceEngine = engine(seed: 11)
        var previous = -1.0
        for step in stride(from: 0.0, through: raceEngine.plan.finishTime + 60, by: 5) {
            let progress = raceEngine.plan.progress(at: step)
            XCTAssertGreaterThanOrEqual(progress, previous - 0.0001, "進捗が戻っている")
            XCTAssertLessThanOrEqual(progress, 1.0)
            previous = progress
        }
        XCTAssertEqual(raceEngine.plan.progress(at: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(raceEngine.plan.progress(at: raceEngine.plan.finishTime), 1, accuracy: 0.0001)
        XCTAssertEqual(raceEngine.plan.progress(at: -10), 0, accuracy: 0.0001)
    }

    func testActivityBecomesFinishedAfterGoal() {
        let raceEngine = engine(seed: 6)
        XCTAssertEqual(raceEngine.plan.activity(at: raceEngine.plan.finishTime + 1), .finished)
        XCTAssertNotEqual(raceEngine.plan.activity(at: 0), .finished)
    }

    // MARK: - ゴール時間

    func testCharacterFinishTimeIsCloseToTarget() {
        for seed in UInt64(1) ... 40 {
            let raceEngine = engine(minutes: 20, seed: seed)
            let target = raceEngine.configuration.targetDuration
            XCTAssertGreaterThanOrEqual(raceEngine.plan.finishTime, target * 0.85)
            XCTAssertLessThanOrEqual(raceEngine.plan.finishTime, target * 1.12)
        }
    }

    func testFinishTimeVariesBetweenRuns() {
        let times = (UInt64(1) ... 12).map { engine(seed: $0).plan.finishTime }
        XCTAssertGreaterThan(Set(times.map { ($0 * 100).rounded() }).count, 1, "毎回まったく同じではない")
    }

    func testSameSeedProducesSamePlan() {
        XCTAssertEqual(engine(seed: 777).plan, engine(seed: 777).plan)
    }

    func testCalmerCharacterHasSmallerSpread() {
        // 性格の paceVariance が小さいほど、ゴール時間のばらつきが小さい
        func spread(for personality: CharacterPersonality) -> Double {
            let times = (UInt64(1) ... 60).map { seed -> Double in
                MealRaceEngine.characterFinishTime(
                    targetDuration: 900,
                    personality: personality,
                    random: SeededRandomSource(seed: seed)
                )
            }
            return (times.max() ?? 0) - (times.min() ?? 0)
        }
        XCTAssertLessThan(spread(for: .steady), spread(for: .playful))
    }

    // MARK: - 子どもの進捗

    func testChildProgressFollowsElapsedTime() {
        let raceEngine = engine(minutes: 10)
        XCTAssertEqual(raceEngine.childProgress(elapsed: 0, bites: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(raceEngine.childProgress(elapsed: 300, bites: 0), 0.5, accuracy: 0.0001)
    }

    func testBitesGiveABoundedBoost() {
        let raceEngine = engine(minutes: 10)
        let withoutBites = raceEngine.childProgress(elapsed: 120, bites: 0)
        let withBites = raceEngine.childProgress(elapsed: 120, bites: 5)
        XCTAssertGreaterThan(withBites, withoutBites)

        let manyBites = raceEngine.childProgress(elapsed: 120, bites: 1000)
        XCTAssertEqual(
            manyBites - withoutBites,
            MealRaceEngine.maximumBiteBonus,
            accuracy: 0.0001,
            "タップだけで一気にゴールできないようにする"
        )
    }

    func testChildProgressNeverReachesOneWithoutTheButton() {
        let raceEngine = engine(minutes: 10)
        XCTAssertLessThanOrEqual(
            raceEngine.childProgress(elapsed: 100_000, bites: 10_000),
            MealRaceEngine.childProgressCeiling
        )
        XCTAssertLessThan(raceEngine.childProgress(elapsed: 100_000, bites: 10_000), 1.0)
    }

    // MARK: - スナップショット

    func testSnapshotReportsLeader() {
        let raceEngine = engine(minutes: 10, seed: 42)
        let early = raceEngine.snapshot(at: 60, bites: 60)
        XCTAssertEqual(early.leader, .child, "たくさん食べればリードできる")

        let stalled = raceEngine.snapshot(at: raceEngine.plan.finishTime, bites: 0)
        XCTAssertEqual(stalled.leader, .character)
    }

    func testSnapshotRemainingTimeNeverGoesNegative() {
        let raceEngine = engine(minutes: 10)
        XCTAssertEqual(raceEngine.snapshot(at: 0).remainingToTarget, 600, accuracy: 0.001)
        XCTAssertEqual(raceEngine.snapshot(at: 9_999).remainingToTarget, 0, accuracy: 0.001)
    }

    func testCharacterFinishedFlag() {
        let raceEngine = engine(seed: 15)
        XCTAssertFalse(raceEngine.hasCharacterFinished(at: 0))
        XCTAssertTrue(raceEngine.hasCharacterFinished(at: raceEngine.plan.finishTime))
        XCTAssertTrue(raceEngine.snapshot(at: raceEngine.plan.finishTime + 5).characterHasFinished)
    }

    // MARK: - 終了判定

    func testChildFinishingFirstIsCelebrated() {
        let raceEngine = engine(minutes: 15, seed: 21)
        let result = raceEngine.finish(at: 60, childName: "さくら")
        XCTAssertTrue(result.childFinishedFirst)
        XCTAssertEqual(result.starsEarned, 3)
        XCTAssertTrue(result.subline.contains("さくら"))
        XCTAssertTrue(result.subline.contains("くまくん"))
        XCTAssertTrue(result.subline.contains("はやかった"))
    }

    func testCharacterFinishingFirstStaysPositive() {
        let raceEngine = engine(minutes: 15, seed: 21)
        let result = raceEngine.finish(at: raceEngine.plan.finishTime + 120, childName: "さくら")
        XCTAssertFalse(result.childFinishedFirst)
        XCTAssertEqual(result.starsEarned, 2, "遅くても必ず★がもらえる")

        let forbidden = ["まけ", "まけた", "じかんぎれ", "おそい", "ざんねん", "だめ"]
        for word in forbidden {
            XCTAssertFalse(result.headline.contains(word), "「\(result.headline)」に否定語")
            XCTAssertFalse(result.subline.contains(word), "「\(result.subline)」に否定語")
        }
    }

    func testCharacterMessagesAreEncouraging() {
        let raceEngine = engine(minutes: 15, seed: 8)
        let forbidden = ["まけ", "じかんぎれ", "おそい", "ざんねん", "だめ", "はやくして"]
        for step in stride(from: 0.0, through: raceEngine.plan.finishTime + 300, by: 7) {
            let message = raceEngine.message(at: step, childName: "さくら")
            XCTAssertFalse(message.isEmpty)
            for word in forbidden {
                XCTAssertFalse(message.contains(word), "「\(message)」に否定語")
            }
        }
    }

    func testCharacterFinishedMessageEncouragesInstead() {
        let raceEngine = engine(minutes: 15, seed: 8)
        let message = raceEngine.message(at: raceEngine.plan.finishTime + 10, childName: "さくら")
        XCTAssertTrue(message.contains("あとちょっと"))
    }

    func testIntroLineNamesTheCharacter() {
        let raceEngine = engine(characterID: "usa")
        XCTAssertTrue(raceEngine.character.raceIntroLine.contains("うさぴょん"))
        XCTAssertTrue(raceEngine.character.raceIntroLine.contains("きょうそう"))
    }

    func testUnknownCharacterFallsBack() {
        let raceEngine = engine(characterID: "does-not-exist")
        XCTAssertEqual(raceEngine.character.id, CharacterCatalog.defaultCharacterID)
    }

    func testConfigurationClampsVeryShortDurations() {
        let configuration = MealRaceConfiguration(targetDuration: 5, characterID: "piyo", seed: 1)
        XCTAssertEqual(configuration.targetDuration, 60, accuracy: 0.001)
    }

    func testConfigurationFromSettings() {
        var settings = AppSettings.default
        settings.mealDurationMinutes = 20
        settings.mealCharacterID = "pen"
        let configuration = MealRaceConfiguration(settings: settings, seed: 3)
        XCTAssertEqual(configuration.targetDuration, 1200, accuracy: 0.001)
        XCTAssertEqual(configuration.characterID, "pen")
    }
}

final class UnlockEvaluatorTests: XCTestCase {

    func testAlwaysItemsAreUnlockedFromTheStart() {
        let evaluator = UnlockEvaluator()
        let unlocked = evaluator.unlockedIDs(progress: UnlockProgress())
        XCTAssertTrue(unlocked.contains("char.piyo"))
        XCTAssertTrue(unlocked.contains("ware.white"))
        XCTAssertEqual(unlocked, UnlockCatalog.initiallyUnlockedIDs)
    }

    func testStarConditions() {
        let evaluator = UnlockEvaluator()
        XCTAssertFalse(evaluator.isSatisfied(.totalStars(30), progress: UnlockProgress(totalStars: 29)))
        XCTAssertTrue(evaluator.isSatisfied(.totalStars(30), progress: UnlockProgress(totalStars: 30)))
    }

    func testSubjectMasteryCondition() {
        let evaluator = UnlockEvaluator()
        let progress = UnlockProgress(subjectMastery: [.hiragana: 0.65])
        XCTAssertTrue(evaluator.isSatisfied(.subjectMastery(.hiragana, 0.6), progress: progress))
        XCTAssertFalse(evaluator.isSatisfied(.subjectMastery(.hiragana, 0.7), progress: progress))
        XCTAssertFalse(evaluator.isSatisfied(.subjectMastery(.number, 0.1), progress: UnlockProgress()))
    }

    func testNewlyUnlockedReportsOnlyTheDifference() {
        let evaluator = UnlockEvaluator()
        let previously = UnlockCatalog.initiallyUnlockedIDs
        let newItems = evaluator.newlyUnlocked(
            previouslyUnlocked: previously,
            progress: UnlockProgress(totalStars: 30)
        )
        let ids = Set(newItems.map(\.id))
        XCTAssertTrue(ids.contains("char.nyan"))
        XCTAssertTrue(ids.contains("costume.cap"))
        XCTAssertTrue(ids.contains("bg.park"))
        XCTAssertFalse(ids.contains("char.piyo"), "すでに解放済みのものは報告しない")
    }

    func testNextGoalPointsAtSomethingAchievable() {
        let evaluator = UnlockEvaluator()
        let progress = UnlockProgress(totalStars: 9)
        let unlocked = evaluator.unlockedIDs(progress: progress)
        let goal = evaluator.nextGoal(progress: progress, unlocked: unlocked)
        XCTAssertEqual(goal?.id, "costume.cap", "★10 がいちばん近い目標")
        XCTAssertFalse(goal?.condition.childDescription.isEmpty ?? true)
    }

    func testAvailableCharactersFollowUnlocks() {
        let evaluator = UnlockEvaluator()
        let initial = evaluator.availableCharacters(unlocked: UnlockCatalog.initiallyUnlockedIDs)
        XCTAssertEqual(Set(initial.map(\.id)), ["piyo", "kuma"])

        let later = evaluator.availableCharacters(
            unlocked: evaluator.unlockedIDs(progress: UnlockProgress(totalStars: 30))
        )
        XCTAssertTrue(later.contains { $0.id == "nyan" })
    }

    func testCatalogIntegrity() {
        XCTAssertEqual(Set(UnlockCatalog.all.map(\.id)).count, UnlockCatalog.all.count, "ID が重複している")
        for item in UnlockCatalog.items(in: .character) {
            XCTAssertNotNil(CharacterCatalog.character(id: item.artKey), "\(item.id) のキャラクターが無い")
        }
        XCTAssertEqual(
            Set(CharacterCatalog.all.map(\.id)),
            Set(UnlockCatalog.items(in: .character).map(\.artKey)),
            "すべてのキャラクターにアンロック定義が必要"
        )
    }

    func testStarRule() {
        XCTAssertEqual(StarRule.stars(forAttemptIndex: 1, judgement: .correct), 2)
        XCTAssertEqual(StarRule.stars(forAttemptIndex: 2, judgement: .correct), 1)
        XCTAssertEqual(StarRule.stars(forAttemptIndex: 3, judgement: .correct), 1)
        XCTAssertEqual(StarRule.stars(forAttemptIndex: 1, judgement: .incorrect), 0)
        XCTAssertEqual(StarRule.stars(forAttemptIndex: 1, judgement: .unclear), 0)
    }
}
