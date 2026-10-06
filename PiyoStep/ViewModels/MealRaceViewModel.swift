import Foundation
import Observation
import PiyoCore

/// ご飯タイマー（キャラクターとの競争）の画面ロジック。
@MainActor
@Observable
final class MealRaceViewModel {

    enum Stage: Equatable {
        case ready
        case countdown(Int)
        case racing
        case finished
    }

    private let environment: AppEnvironment
    private(set) var engine: MealRaceEngine
    private var timer: Timer?
    private var startedAt: Date?
    private var hasAnnouncedCharacterFinish = false
    /// 直近に読み上げた声かけ。同じことばを続けて言わない。
    private var lastSpokenLine: String?
    /// 読み上げ済みの「残り時間」の区切り（秒）。
    private var announcedRemaining: Set<Int> = []
    /// 区切りの声かけを、少しのあいだ吹き出しに残しておく期限。
    private var messagePinnedUntil: Date?
    private(set) var stage: Stage = .ready
    private(set) var elapsed: TimeInterval = 0
    private(set) var snapshot: MealRaceSnapshot
    private(set) var characterMessage: String = ""
    private(set) var result: MealRaceResult?

    /// タイマーの刻み。UI テストでは短くする。
    private let tickInterval: TimeInterval = 0.5

    init(environment: AppEnvironment) {
        self.environment = environment
        let configuration = environment.makeMealConfiguration()
        let raceEngine = MealRaceEngine(configuration: configuration)
        self.engine = raceEngine
        self.snapshot = raceEngine.snapshot(at: 0)
        self.characterMessage = raceEngine.character.raceIntroLine
    }

    var character: CharacterDefinition { engine.character }
    var childName: String { environment.profile?.callName ?? "きみ" }

    var targetMinutes: Int {
        Int((engine.configuration.targetDuration / 60).rounded())
    }

    /// 準備画面で選べる時間（分）。
    static let selectableMinutes = [5, 10, 15, 20, 30, 40, 60]

    /// 時間を選び直す。始まってからは変えられない。
    /// 選んだ時間は設定にも保存して、次回もその時間で始められるようにする。
    func select(minutes: Int) {
        guard stage == .ready, minutes != targetMinutes else { return }
        let clamped = min(
            max(minutes, AppSettings.mealDurationRange.lowerBound),
            AppSettings.mealDurationRange.upperBound
        )
        var settings = environment.settings
        settings.mealDurationMinutes = clamped
        environment.update(settings: settings)

        let raceEngine = MealRaceEngine(configuration: environment.makeMealConfiguration())
        engine = raceEngine
        snapshot = raceEngine.snapshot(at: 0)
        characterMessage = raceEngine.character.raceIntroLine
        environment.haptics.tap()
    }

    var remainingText: String {
        let remaining = Int(snapshot.remainingToTarget.rounded())
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// キャラクターの今の様子（イラスト用）。
    var characterMood: CharacterMood {
        switch snapshot.characterActivity {
        case .eating: return .eating
        case .resting: return .resting
        case .cheering: return .cheering
        case .finished: return .cheering
        }
    }

    /// キャラクター側のお皿の残り。
    var characterPlateFullness: Double {
        max(0, 1 - snapshot.characterProgress)
    }

    // MARK: - 進行

    func begin() {
        guard stage == .ready else { return }
        environment.adPresenter.isLearningSessionActive = true
        // 始まりのセリフはスタート前の画面を開いたときに読み上げている。
        // ここでも言うと 2 回続けて聞こえるので、読みかけなら止めるだけにする。
        environment.stopSpeaking()
        runCountdown(from: 3)
    }

    private func runCountdown(from value: Int) {
        guard value > 0 else {
            startRace()
            return
        }
        stage = .countdown(value)
        environment.play(.tap)
        let delay = environment.launchArguments.reduceAnimations ? 0.15 : 0.9
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.runCountdown(from: value - 1)
            }
        }
    }

    private func startRace() {
        stage = .racing
        startedAt = environment.clock.now
        elapsed = 0
        hasAnnouncedCharacterFinish = false
        announcedRemaining = []
        messagePinnedUntil = nil
        characterMessage = engine.character.eatLine
        // 食べ始めのセリフはカウントダウンのあとすぐには読まず、次に様子が変わったときに声をかける。
        lastSpokenLine = characterMessage
        environment.play(.mealStart)
        updateSnapshot()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard stage == .racing, let startedAt else { return }
        elapsed = environment.clock.now.timeIntervalSince(startedAt)
        updateSnapshot()
        announceRemainingIfNeeded()

        if engine.hasCharacterFinished(at: elapsed), !hasAnnouncedCharacterFinish {
            hasAnnouncedCharacterFinish = true
            // 「まけ」ではなく、応援に切り替える。
            characterMessage = engine.character.characterFinishedLine
            environment.speak(characterMessage)
        }
    }

    private func updateSnapshot() {
        snapshot = engine.snapshot(at: elapsed)
        guard !hasAnnouncedCharacterFinish else { return }
        // 区切りの声かけを出している間は、そのまま残す。
        if let until = messagePinnedUntil {
            if environment.clock.now < until { return }
            messagePinnedUntil = nil
        }
        let line = engine.message(at: elapsed, childName: childName)
        characterMessage = line
        speakIfChanged(line)
    }

    /// 食べる・休む・応援する が切り替わったときだけ声をかける。
    /// 毎回しゃべるとうるさいので、ことばが変わったときに限る。
    private func speakIfChanged(_ line: String) {
        guard stage == .racing, line != lastSpokenLine else { return }
        lastSpokenLine = line
        environment.speak(line)
    }

    /// 残り時間の区切りで声をかける。半分すぎたときと、のこり1分。
    private func announceRemainingIfNeeded() {
        guard stage == .racing else { return }
        let target = Int(engine.configuration.targetDuration.rounded())
        let remaining = Int(snapshot.remainingToTarget.rounded())
        let milestones = [target / 2, 60].filter { $0 > 5 && $0 < target }

        for milestone in milestones.sorted(by: >)
        where !announcedRemaining.contains(milestone) && remaining <= milestone {
            announcedRemaining.insert(milestone)
            let line = milestone == 60 ? "のこり 1ぷん！ がんばろう！" : "はんぶん すぎたよ！"
            characterMessage = line
            messagePinnedUntil = environment.clock.now.addingTimeInterval(4)
            lastSpokenLine = line
            environment.speak(line)
            return
        }
    }

    /// 「たべおわった！」
    func finish() {
        guard stage != .finished, stage != .ready else { return }
        timer?.invalidate()
        timer = nil

        let outcome = engine.finish(at: elapsed, childName: childName)
        result = outcome
        stage = .finished
        environment.adPresenter.isLearningSessionActive = false
        environment.play(.mealFinish)
        environment.haptics.success()
        environment.speak("\(outcome.headline) \(outcome.subline)")

        let record = MealSessionRecord(
            characterID: engine.character.id,
            targetDuration: engine.configuration.targetDuration,
            actualDuration: elapsed,
            childFinishedFirst: outcome.childFinishedFirst,
            startedAt: startedAt ?? environment.clock.now
        )
        environment.process(meal: record, starsEarned: outcome.starsEarned)
    }

    /// 画面を閉じるときの後始末。
    func cancel() {
        timer?.invalidate()
        timer = nil
        environment.adPresenter.isLearningSessionActive = false
        environment.stopSpeaking()
    }
}
