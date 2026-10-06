import XCTest
@testable import PiyoCore

final class SessionReviewTests: XCTestCase {

    private func attempt(
        _ skill: Skill,
        _ judgement: AnswerJudgement,
        attemptIndex: Int,
        mode: AnswerMode = .choice,
        offset: TimeInterval
    ) -> AttemptRecord {
        AttemptRecord(
            skill: skill,
            difficulty: .level2,
            judgement: judgement,
            answerMode: mode,
            attemptIndex: attemptIndex,
            duration: 3,
            createdAt: Fixture.referenceDate.addingTimeInterval(offset)
        )
    }

    private func summary(_ attempts: [AttemptRecord]) -> SessionSummary {
        SessionSummary(
            record: SessionRecord(
                kind: .freePlay,
                subject: .hiragana,
                startedAt: Fixture.referenceDate,
                endedAt: Fixture.referenceDate.addingTimeInterval(60),
                questionCount: SessionReview.groupIntoQuestions(attempts).count,
                correctCount: attempts.filter { $0.judgement == .correct }.count,
                starsEarned: 2
            ),
            attempts: attempts
        )
    }

    func testGroupsAttemptsIntoQuestions() {
        let attempts = [
            attempt(.hiraganaRead, .correct, attemptIndex: 1, offset: 0),
            attempt(.hiraganaRead, .incorrect, attemptIndex: 1, offset: 10),
            attempt(.hiraganaRead, .correct, attemptIndex: 2, offset: 20),
            attempt(.numberCount, .incorrect, attemptIndex: 1, offset: 30)
        ]
        let questions = SessionReview.groupIntoQuestions(attempts)
        XCTAssertEqual(questions.count, 3)
        XCTAssertEqual(questions[1].count, 2, "やり直しは同じ問題にまとめる")
    }

    func testCountsFirstTryAndRetry() {
        let attempts = [
            attempt(.hiraganaRead, .correct, attemptIndex: 1, offset: 0),
            attempt(.hiraganaRead, .incorrect, attemptIndex: 1, offset: 10),
            attempt(.hiraganaRead, .correct, attemptIndex: 2, offset: 20)
        ]
        let review = SessionReview.make(from: summary(attempts))
        let outcome = try? XCTUnwrap(review.outcomes.first)
        XCTAssertEqual(outcome?.skill, .hiraganaRead)
        XCTAssertEqual(outcome?.questionCount, 2)
        XCTAssertEqual(outcome?.solvedOnFirstTry, 1)
        XCTAssertEqual(outcome?.solvedAfterRetry, 1)
        XCTAssertEqual(outcome?.unsolved, 0)
    }

    func testUnsolvedQuestionsAreCounted() {
        let attempts = [
            attempt(.numberCount, .incorrect, attemptIndex: 1, offset: 0),
            attempt(.numberCount, .incorrect, attemptIndex: 2, offset: 10),
            attempt(.numberCount, .incorrect, attemptIndex: 3, offset: 20)
        ]
        let review = SessionReview.make(from: summary(attempts))
        XCTAssertEqual(review.outcomes.first?.unsolved, 1)
        XCTAssertFalse(review.watchPoints.isEmpty, "つまずいた点を伝える")
    }

    func testPraisePointsMentionTheStrongSkill() {
        let attempts = [
            attempt(.hiraganaRead, .correct, attemptIndex: 1, offset: 0),
            attempt(.hiraganaRead, .correct, attemptIndex: 1, offset: 10)
        ]
        let review = SessionReview.make(from: summary(attempts))
        XCTAssertTrue(
            review.praisePoints.contains { $0.contains(Skill.hiraganaRead.parentTitle) },
            "得意な Skill の名前を出す"
        )
    }

    func testPraisePointsMentionPersistence() {
        let attempts = [
            attempt(.hiraganaRead, .incorrect, attemptIndex: 1, offset: 0),
            attempt(.hiraganaRead, .correct, attemptIndex: 2, offset: 10)
        ]
        let review = SessionReview.make(from: summary(attempts))
        XCTAssertTrue(review.praisePoints.contains { $0.contains("あきらめないで") })
    }

    func testPraisePointsMentionTracing() {
        let attempts = [
            attempt(.hiraganaWrite, .correct, attemptIndex: 1, mode: .trace, offset: 0)
        ]
        let review = SessionReview.make(from: summary(attempts))
        XCTAssertTrue(review.praisePoints.contains { $0.contains("なぞる") })
    }

    func testPraisePointsAreLimited() {
        let attempts = [
            attempt(.hiraganaRead, .correct, attemptIndex: 1, offset: 0),
            attempt(.hiraganaRead, .incorrect, attemptIndex: 1, offset: 10),
            attempt(.hiraganaRead, .correct, attemptIndex: 2, offset: 20),
            attempt(.hiraganaWrite, .correct, attemptIndex: 1, mode: .trace, offset: 30),
            attempt(.numberCount, .correct, attemptIndex: 1, mode: .voice, offset: 40)
        ]
        let review = SessionReview.make(from: summary(attempts))
        XCTAssertLessThanOrEqual(review.praisePoints.count, SessionReview.maximumPraisePoints)
    }

    func testEmptySessionHasNoOutcomes() {
        let review = SessionReview.make(from: summary([]))
        XCTAssertTrue(review.isEmpty)
        XCTAssertTrue(review.praisePoints.isEmpty)
    }
}
