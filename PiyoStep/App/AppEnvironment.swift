import Foundation
import Observation
import PiyoCore

/// アプリ全体の依存をまとめる単純な DI コンテナ。
/// すべての外部依存は protocol 越しなので、テストでは差し替えられる。
@MainActor
@Observable
final class AppEnvironment {

    // MARK: - サービス

    let settingsStore: SettingsStoring
    let historyStore: LearningHistoryStoring
    let speechRecognizer: SpeechRecognizing
    let speechSynthesizer: SpeechSynthesizing
    let soundPlayer: SoundPlaying
    let haptics: HapticFeedbackProviding
    let purchaseService: PurchaseServing
    let adPresenter: AdPresenting
    let profileImageStore: ProfileImageStoring
    let random: RandomSource
    let clock: ClockProviding

    // MARK: - エンジン

    let questionFactory: QuestionFactory
    let challengeBuilder: DailyChallengeBuilder
    let resultProcessor: LearningResultProcessor
    let unlockEvaluator: UnlockEvaluator
    let aggregator: ProgressAggregator

    // MARK: - 状態

    var profile: ChildProfile?
    var settings: AppSettings
    var progress: ProgressSummary = .empty
    var unlockedItemIDs: Set<String> = UnlockCatalog.initiallyUnlockedIDs
    /// 直近に解放されたもの（演出したら空にする）
    var pendingUnlocks: [UnlockableItem] = []
    /// 保護者画面に入るときの広告を表示中か
    var isShowingParentAd = false
    /// この起動で、すでに大人がペアレンタルゲートを通ったか。
    /// 遊ぶたびに計算を解かせると手間なので、起動につき 1 回だけ確認する。
    private(set) var hasPassedParentGateThisLaunch = false

    let launchArguments: LaunchArguments

    init(
        settingsStore: SettingsStoring,
        historyStore: LearningHistoryStoring,
        speechRecognizer: SpeechRecognizing,
        speechSynthesizer: SpeechSynthesizing,
        soundPlayer: SoundPlaying,
        haptics: HapticFeedbackProviding,
        purchaseService: PurchaseServing,
        adPresenter: AdPresenting,
        profileImageStore: ProfileImageStoring = InMemoryProfileImageStore(),
        random: RandomSource = SystemRandomSource(),
        clock: ClockProviding = SystemClock(),
        launchArguments: LaunchArguments = .none
    ) {
        self.settingsStore = settingsStore
        self.historyStore = historyStore
        self.speechRecognizer = speechRecognizer
        self.speechSynthesizer = speechSynthesizer
        self.soundPlayer = soundPlayer
        self.haptics = haptics
        self.purchaseService = purchaseService
        self.adPresenter = adPresenter
        self.profileImageStore = profileImageStore
        self.random = random
        self.clock = clock
        self.launchArguments = launchArguments

        let factory = QuestionFactory()
        self.questionFactory = factory
        self.challengeBuilder = DailyChallengeBuilder(factory: factory)
        self.resultProcessor = LearningResultProcessor()
        self.unlockEvaluator = UnlockEvaluator()
        self.aggregator = ProgressAggregator()

        self.settings = settingsStore.load()
        self.profile = settingsStore.loadProfile()
    }

    // MARK: - 起動

    func bootstrap() {
        if launchArguments.forceFreshInstall {
            profile = nil
            settingsStore.saveProfile(nil)
        } else if let seededName = launchArguments.seededProfileName, profile == nil {
            let seeded = ChildProfile(
                nickname: seededName,
                age: launchArguments.seededProfileAge,
                createdAt: clock.now
            )
            profile = seeded
            settingsStore.saveProfile(seeded)
        }

        if let seconds = launchArguments.mealDurationSeconds {
            settings.mealDurationMinutes = max(1, seconds / 60)
        }

        haptics.isEnabledIfSupported(settings.hapticsEnabled)
        refreshProgress()
    }

    func loadPurchases() async {
        await purchaseService.loadProducts()
        if purchaseService.isAdFreePurchased, !settings.adsRemoved {
            var updated = settings
            updated.adsRemoved = true
            update(settings: updated)
        }
    }

    /// ペアレンタルゲートを通ったことを覚えておく。
    func markParentGatePassed() {
        hasPassedParentGateThisLaunch = true
    }

    // MARK: - プロフィール・設定

    func save(profile newProfile: ChildProfile) {
        // 使われなくなった写真は消しておく（端末に溜めない）。
        if let oldPhoto = profile?.avatar.photoFileName,
           oldPhoto != newProfile.avatar.photoFileName {
            profileImageStore.delete(named: oldPhoto)
        }
        profile = newProfile
        settingsStore.saveProfile(newProfile)
    }

    /// アプリの中で使う呼び名。ホーム画面のアプリ名は iOS では変えられない。
    var appDisplayName: String {
        AppNaming.displayName(custom: settings.appDisplayName)
    }

    /// いま選ばれているアイコン。
    var avatar: ProfileAvatar {
        profile?.avatar ?? .default
    }

    /// アイコン写真の中身。無ければ nil（呼び出し側はキャラクターの絵を出す）。
    func avatarImageData() -> Data? {
        guard let name = avatar.photoFileName else { return nil }
        return profileImageStore.imageData(named: name)
    }

    /// 写真を保存してアイコンに設定する。保存できなければ false。
    @discardableResult
    func updateAvatarPhoto(data: Data) -> Bool {
        guard let profile, let name = profileImageStore.save(imageData: data) else { return false }
        var updated = profile
        updated.avatar = .photo(name)
        save(profile: updated)
        return true
    }

    /// 写真をやめて、キャラクターの絵に戻す。
    func updateAvatar(characterID: String) {
        guard let profile else { return }
        var updated = profile
        updated.avatar = .character(characterID)
        save(profile: updated)
    }

    func update(settings newSettings: AppSettings) {
        settings = newSettings.sanitized()
        settingsStore.save(settings)
        haptics.isEnabledIfSupported(settings.hapticsEnabled)
    }

    // MARK: - 音

    /// 読み上げ。設定で OFF のときは何もしない。
    func speak(_ text: String, locale: RecognitionLocale = .japanese) {
        guard settings.voiceGuidanceEnabled, settings.volume > 0.01 else { return }
        speechSynthesizer.speak(text, locale: locale, volume: settings.volume)
    }

    func stopSpeaking() {
        speechSynthesizer.stop()
    }

    func play(_ effect: SoundEffect) {
        soundPlayer.play(effect, volume: settings.volume)
    }

    // MARK: - 出題

    /// 今日のチャレンジをつくる。
    func makeDailyChallenge() -> DailyChallenge {
        let currentProfile = profile ?? ChildProfile(nickname: "", age: 4, createdAt: clock.now)
        return challengeBuilder.build(
            profile: currentProfile,
            settings: settings,
            snapshots: historyStore.masterySnapshots(),
            recentAttempts: historyStore.attempts(limit: 40),
            now: clock.now,
            random: random
        )
    }

    /// 教科メニューから 1 つの Skill を連続で練習する。
    func makeFreePlayQuestions(skill: Skill, count: Int = 6) -> [Question] {
        let snapshots = historyStore.masterySnapshots()
        let level = challengeBuilder.level(
            for: skill,
            snapshot: snapshots[skill],
            settings: settings,
            profile: profile ?? ChildProfile(nickname: "", age: 4, createdAt: clock.now),
            recentAttempts: historyStore.attempts(limit: 40)
        )
        return (0 ..< max(1, count)).compactMap { _ in
            questionFactory.makeQuestion(
                skill: skill,
                level: level,
                random: random,
                allowVoice: settings.voiceAnswerEnabled
            )
        }
    }

    /// その Skill の現在の難易度（画面表示用）。
    func currentLevel(for skill: Skill) -> DifficultyLevel {
        let snapshots = historyStore.masterySnapshots()
        return challengeBuilder.level(
            for: skill,
            snapshot: snapshots[skill],
            settings: settings,
            profile: profile ?? ChildProfile(nickname: "", age: 4, createdAt: clock.now),
            recentAttempts: []
        )
    }

    // MARK: - 結果の反映

    func process(summary: SessionSummary) {
        let outcome = resultProcessor.process(
            summary: summary,
            settings: settings,
            store: historyStore,
            now: clock.now
        )
        apply(outcome: outcome)
    }

    func process(meal record: MealSessionRecord, starsEarned: Int) {
        let outcome = resultProcessor.process(
            meal: record,
            starsEarned: starsEarned,
            store: historyStore,
            now: clock.now
        )
        apply(outcome: outcome)
    }

    private func apply(outcome: LearningResultOutcome) {
        progress = outcome.summary
        unlockedItemIDs = historyStore.unlockedItemIDs()
        if !outcome.newlyUnlocked.isEmpty {
            pendingUnlocks.append(contentsOf: outcome.newlyUnlocked)
            play(.unlock)
        }
    }

    func refreshProgress() {
        progress = aggregator.summarize(
            attempts: historyStore.attempts(),
            sessions: historyStore.sessions(),
            mealSessions: historyStore.mealSessions(),
            snapshots: historyStore.masterySnapshots(),
            now: clock.now
        )
        unlockedItemIDs = historyStore.unlockedItemIDs()
    }

    func consumePendingUnlocks() -> [UnlockableItem] {
        let items = pendingUnlocks
        pendingUnlocks = []
        return items
    }

    // MARK: - コレクション

    func isUnlocked(_ itemID: String) -> Bool {
        unlockedItemIDs.contains(itemID)
    }

    var availableCharacters: [CharacterDefinition] {
        let characters = unlockEvaluator.availableCharacters(unlocked: unlockedItemIDs)
        return characters.isEmpty ? [CharacterCatalog.fallback] : characters
    }

    var buddyCharacter: CharacterDefinition {
        CharacterCatalog.character(id: profile?.buddyCharacterID ?? CharacterCatalog.defaultCharacterID)
            ?? CharacterCatalog.fallback
    }

    var mealCharacter: CharacterDefinition {
        CharacterCatalog.character(id: settings.mealCharacterID) ?? CharacterCatalog.fallback
    }

    var nextUnlockGoal: UnlockableItem? {
        let unlockProgress = aggregator.unlockProgress(
            from: progress,
            snapshots: historyStore.masterySnapshots()
        )
        return unlockEvaluator.nextGoal(progress: unlockProgress, unlocked: unlockedItemIDs)
    }

    // MARK: - 音声回答が使えるか

    func canUseVoice(for locale: RecognitionLocale) -> Bool {
        settings.voiceAnswerEnabled && speechRecognizer.isAvailable(for: locale)
    }

    /// ご飯タイマーの設定。毎回すこし違う結果になるようシードを変える。
    func makeMealConfiguration() -> MealRaceConfiguration {
        let seed: UInt64
        if let fixed = launchArguments.randomSeed {
            seed = fixed
        } else {
            seed = UInt64(UInt32.random(in: 0 ... UInt32.max))
        }
        var configuration = MealRaceConfiguration(settings: settings, seed: seed)
        if let seconds = launchArguments.mealDurationSeconds {
            configuration = MealRaceConfiguration(
                targetDuration: TimeInterval(seconds),
                characterID: settings.mealCharacterID,
                seed: seed
            )
        }
        return configuration
    }
}

extension HapticFeedbackProviding {
    /// 設定のオン・オフを反映する（実装が対応していれば）。
    func isEnabledIfSupported(_ enabled: Bool) {
        (self as? SystemHapticsService)?.isEnabled = enabled
    }
}
