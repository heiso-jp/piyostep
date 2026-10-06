import XCTest
@testable import PiyoCore

final class ItemMasteryEstimatorTests: XCTestCase {

    private func attempt(
        item: LearningItemID?,
        ability: LearningAbility?,
        judgement: AnswerJudgement,
        skill: Skill = .hiraganaRead,
        mode: AnswerMode = .choice,
        offset: TimeInterval
    ) -> AttemptRecord {
        AttemptRecord(
            skill: skill,
            difficulty: .level2,
            judgement: judgement,
            answerMode: mode,
            duration: 2,
            createdAt: Fixture.referenceDate.addingTimeInterval(offset),
            itemID: item,
            ability: ability
        )
    }

    private let あ = LearningItemID.kana("あ", subject: .hiragana)

    func testOneCorrectAnswerIsFullMastery() {
        let estimator = ItemMasteryEstimator()
        let snapshots = estimator.snapshots(from: [
            attempt(item: あ, ability: .read, judgement: .correct, offset: 0)
        ])
        XCTAssertEqual(snapshots["hiragana.あ.read"]?.percent, 100)
    }

    func testWrongAnswerPullsMasteryDown() {
        let estimator = ItemMasteryEstimator(alpha: 0.5)
        let snapshots = estimator.snapshots(from: [
            attempt(item: あ, ability: .read, judgement: .correct, offset: 0),
            attempt(item: あ, ability: .read, judgement: .incorrect, offset: 10)
        ])
        let mastery = snapshots["hiragana.あ.read"]
        XCTAssertEqual(mastery?.percent, 50)
        XCTAssertEqual(mastery?.attempts, 2)
        XCTAssertEqual(mastery?.correctCount, 1)
    }

    func testReadAndWriteAreTrackedSeparately() {
        let estimator = ItemMasteryEstimator()
        let snapshots = estimator.snapshots(from: [
            attempt(item: あ, ability: .read, judgement: .correct, offset: 0),
            attempt(item: あ, ability: .write, judgement: .incorrect,
                    skill: .hiraganaWrite, mode: .trace, offset: 10)
        ])
        XCTAssertEqual(snapshots["hiragana.あ.read"]?.percent, 100)
        XCTAssertEqual(snapshots["hiragana.あ.write"]?.percent, 0)
    }

    func testUnclearAnswersDoNotCount() {
        let estimator = ItemMasteryEstimator()
        let snapshots = estimator.snapshots(from: [
            attempt(item: あ, ability: .read, judgement: .correct, offset: 0),
            attempt(item: あ, ability: .read, judgement: .unclear, offset: 10)
        ])
        XCTAssertEqual(snapshots["hiragana.あ.read"]?.attempts, 1)
        XCTAssertEqual(snapshots["hiragana.あ.read"]?.percent, 100)
    }

    func testTracingIsCountedAsPracticeOnly() {
        let estimator = ItemMasteryEstimator()
        let attempts = [
            attempt(item: あ, ability: nil, judgement: .correct,
                    skill: .hiraganaWrite, mode: .trace, offset: 0)
        ]
        XCTAssertTrue(estimator.snapshots(from: attempts).isEmpty, "なぞりは習熟度に入れない")
        XCTAssertEqual(estimator.practiceCounts(from: attempts)[あ], 1)
    }

    func testAttemptsWithoutItemAreIgnored() {
        let estimator = ItemMasteryEstimator()
        let snapshots = estimator.snapshots(from: [
            attempt(item: nil, ability: .read, judgement: .correct, offset: 0)
        ])
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testAveragePercentUsesPractisedItemsOnly() {
        let estimator = ItemMasteryEstimator()
        let い = LearningItemID.kana("い", subject: .hiragana)
        let snapshots = estimator.snapshots(from: [
            attempt(item: あ, ability: .read, judgement: .correct, offset: 0),
            attempt(item: い, ability: .read, judgement: .incorrect, offset: 10)
        ])
        XCTAssertEqual(
            estimator.averagePercent(for: .hiragana, ability: .read, in: snapshots),
            50
        )
        XCTAssertNil(estimator.averagePercent(for: .katakana, ability: .read, in: snapshots))
    }

    func testItemIDRoundTripsThroughRawValue() {
        XCTAssertEqual(LearningItemID(rawValue: "hiragana.あ"), あ)
        XCTAssertEqual(LearningItemID(rawValue: "number.7"), .number(7))
        XCTAssertNil(LearningItemID(rawValue: "unknown.x"))
        XCTAssertNil(LearningItemID(rawValue: "hiragana."))
        XCTAssertNil(LearningItemID(rawValue: "hiragana"))
    }
}
