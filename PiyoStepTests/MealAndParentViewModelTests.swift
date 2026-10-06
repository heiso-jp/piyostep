import XCTest
import PiyoCore
@testable import PiyoStep

@MainActor
final class MealRaceViewModelTests: XCTestCase {

    private func makeEnvironment(
        minutes: Int = 15,
        characterID: String = "kuma",
        store: LearningHistoryStoring = InMemoryLearningHistoryStore()
    ) -> AppEnvironment {
        var settings = AppSettings.default
        settings.mealDurationMinutes = minutes
        settings.mealCharacterID = characterID
        return TestEnvironment.make(settings: settings, historyStore: store)
    }

    func testStartsInReadyState() {
        let model = MealRaceViewModel(environment: makeEnvironment())
        XCTAssertEqual(model.stage, .ready)
        XCTAssertEqual(model.targetMinutes, 15)
        XCTAssertEqual(model.character.id, "kuma")
        XCTAssertTrue(model.characterMessage.contains("きょうそう"))
    }

    func testBeginStartsTheCountdownThenRaces() {
        let model = MealRaceViewModel(environment: makeEnvironment())
        model.begin()
        XCTAssertEqual(model.stage, .countdown(3))

        TestEnvironment.wait(timeout: 3.0, until: { model.stage == .racing })
        XCTAssertEqual(model.stage, .racing)
    }

    func testCharacterPlateEmptiesAsTimePasses() {
        let model = MealRaceViewModel(environment: makeEnvironment())
        model.begin()
        TestEnvironment.wait(timeout: 3.0, until: { model.stage == .racing })

        // 始まった直後はキャラクターのお皿がまだいっぱいにある。
        XCTAssertGreaterThan(model.characterPlateFullness, 0.9)
        XCTAssertEqual(model.snapshot.characterProgress, 0, accuracy: 0.05)
    }

    func testFinishingEarlyBeatsTheCharacter() {
        let store = InMemoryLearningHistoryStore()
        let environment = makeEnvironment(store: store)
        let model = MealRaceViewModel(environment: environment)
        model.begin()
        TestEnvironment.wait(timeout: 3.0, until: { model.stage == .racing })

        model.finish()

        XCTAssertEqual(model.stage, .finished)
        XCTAssertTrue(model.result?.childFinishedFirst ?? false)
        XCTAssertEqual(model.result?.starsEarned, 3)
        XCTAssertEqual(store.mealSessions().count, 1)
        XCTAssertEqual(store.sessions().count, 1)
        XCTAssertEqual(environment.progress.mealsCompleted, 1)
    }

    func testResultNeverUsesNegativeWords() {
        let model = MealRaceViewModel(environment: makeEnvironment(minutes: 10))
        model.begin()
        TestEnvironment.wait(timeout: 3.0, until: { model.stage == .racing })
        model.finish()

        let forbidden = ["まけ", "じかんぎれ", "おそい", "ざんねん", "だめ"]
        for word in forbidden {
            XCTAssertFalse(model.result?.headline.contains(word) ?? false)
            XCTAssertFalse(model.result?.subline.contains(word) ?? false)
        }
    }

    func testAdsAreSuppressedDuringTheMeal() {
        let adPresenter = MockAdPresenter(allow: true)
        var settings = AppSettings.default
        settings.mealDurationMinutes = 10
        let environment = TestEnvironment.make(settings: settings, adPresenter: adPresenter)
        let model = MealRaceViewModel(environment: environment)

        model.begin()
        XCTAssertTrue(adPresenter.isLearningSessionActive)
        XCTAssertFalse(adPresenter.shouldPresentParentAd(adsRemoved: false))

        TestEnvironment.wait(timeout: 3.0, until: { model.stage == .racing })
        model.finish()
        XCTAssertFalse(adPresenter.isLearningSessionActive)
    }

    func testCancelStopsEverything() {
        let adPresenter = MockAdPresenter(allow: true)
        let environment = TestEnvironment.make(adPresenter: adPresenter)
        let model = MealRaceViewModel(environment: environment)
        model.begin()
        model.cancel()
        XCTAssertFalse(adPresenter.isLearningSessionActive)
    }

    func testCharacterMoodMirrorsActivity() {
        let model = MealRaceViewModel(environment: makeEnvironment())
        // 開始直後は食べているはず
        XCTAssertEqual(model.engine.plan.activity(at: 1), .eating)
        XCTAssertEqual(model.characterMood, .eating)
    }

    func testRemainingTextCountsDown() {
        let model = MealRaceViewModel(environment: makeEnvironment(minutes: 10))
        XCTAssertEqual(model.remainingText, "10:00")
    }
}

@MainActor
final class ParentGateViewModelTests: XCTestCase {

    func testCorrectAnswerPasses() {
        let model = ParentGateViewModel(random: SeededRandomSource(seed: 5))
        for character in "\(model.challenge.answer)" {
            model.append(digit: character.wholeNumberValue ?? 0)
        }
        XCTAssertTrue(model.submit())
        XCTAssertTrue(model.didPass)
    }

    func testWrongAnswerRegeneratesTheQuestion() {
        let model = ParentGateViewModel(random: SeededRandomSource(seed: 5))
        let first = model.challenge
        model.append(digit: 0)
        XCTAssertFalse(model.submit())
        XCTAssertFalse(model.didPass)
        XCTAssertEqual(model.failedAttempts, 1)
        XCTAssertTrue(model.input.isEmpty)
        XCTAssertNotEqual(model.challenge, first, "同じ問題を出し続けない")
    }

    func testInputIsLimited() {
        let model = ParentGateViewModel(random: SeededRandomSource(seed: 1))
        for _ in 0 ..< 10 {
            model.append(digit: 7)
        }
        XCTAssertEqual(model.input.count, 3)
    }

    func testQuestionIsNotTrivialForAChild() {
        for seed in UInt64(1) ... 30 {
            let model = ParentGateViewModel(random: SeededRandomSource(seed: seed))
            XCTAssertGreaterThanOrEqual(model.challenge.answer, 2)
            XCTAssertTrue(model.questionText.contains("は？"))
        }
    }
}

@MainActor
final class SettingsViewModelTests: XCTestCase {

    func testApplyPersistsSettingsAndProfile() {
        let environment = TestEnvironment.make()
        let model = SettingsViewModel(environment: environment)

        model.childName = "はるき"
        model.childAge = 6
        model.draft.dailyGoal = .plenty
        model.draft.mealDurationMinutes = 20
        model.apply()

        XCTAssertEqual(environment.profile?.nickname, "はるき")
        XCTAssertEqual(environment.profile?.age, 6)
        XCTAssertEqual(environment.settings.dailyGoal, .plenty)
        XCTAssertEqual(environment.settingsStore.load().mealDurationMinutes, 20)
    }

    func testApplyKeepsTheSameProfileIdentity() {
        let environment = TestEnvironment.make()
        let originalID = environment.profile?.id
        let model = SettingsViewModel(environment: environment)
        model.childName = "あたらしいなまえ"
        model.apply()
        XCTAssertEqual(environment.profile?.id, originalID)
    }

    func testTogglingSubjects() {
        let environment = TestEnvironment.make()
        let model = SettingsViewModel(environment: environment)

        XCTAssertTrue(model.isEnabled(subject: .clock))
        model.toggle(subject: .clock)
        XCTAssertFalse(model.isEnabled(subject: .clock))
        XCTAssertFalse(environment.settings.enabledSubjects.contains(.clock))

        model.toggle(subject: .clock)
        XCTAssertTrue(model.isEnabled(subject: .clock))
    }

    func testCannotDisableEverySubject() {
        let environment = TestEnvironment.make()
        let model = SettingsViewModel(environment: environment)
        for subject in Subject.allCases {
            model.toggle(subject: subject)
        }
        XCTAssertFalse(model.draft.enabledSubjects.isEmpty, "最後の 1 つは残す")
    }

    func testAvailableCharactersComeFromUnlocks() {
        let environment = TestEnvironment.make()
        let model = SettingsViewModel(environment: environment)
        XCTAssertEqual(Set(model.availableCharacters.map(\.id)), ["piyo", "kuma"])
    }
}

@MainActor
final class ParentDashboardViewModelTests: XCTestCase {

    func testSummarisesStoredHistory() {
        let store = InMemoryLearningHistoryStore()
        let now = Date()
        for index in 0 ..< 10 {
            store.append(
                attempt: AttemptRecord(
                    skill: .hiraganaRead,
                    difficulty: .level2,
                    judgement: index < 8 ? .correct : .incorrect,
                    answerMode: .choice,
                    createdAt: now
                )
            )
        }
        store.append(
            session: SessionRecord(
                kind: .dailyChallenge,
                startedAt: now,
                endedAt: now.addingTimeInterval(300),
                questionCount: 10,
                correctCount: 8,
                starsEarned: 14
            )
        )

        let environment = TestEnvironment.make(historyStore: store)
        let model = ParentDashboardViewModel(environment: environment)
        model.refresh()

        XCTAssertEqual(model.summary.totalQuestions, 10)
        XCTAssertEqual(model.summary.totalCorrect, 8)
        XCTAssertEqual(model.accuracyText, "80%")
        XCTAssertEqual(model.totalStudyMinutes, 5)
        XCTAssertEqual(model.weeklyStats.count, 7)
        XCTAssertEqual(model.weeklyStats.last?.questionCount, 10)
        XCTAssertFalse(model.summary.recentActivities.isEmpty)
    }

    func testEmptyHistoryIsHandled() {
        let environment = TestEnvironment.make()
        let model = ParentDashboardViewModel(environment: environment)
        model.refresh()
        XCTAssertEqual(model.summary.totalQuestions, 0)
        XCTAssertEqual(model.accuracyText, "—")
        XCTAssertEqual(model.maximumDailyQuestions, 1, "0 除算を避ける")
    }
}
