import Foundation
import Observation
import PiyoCore

/// 保護者画面に入るためのゲート。
@MainActor
@Observable
final class ParentGateViewModel {
    private let random: RandomSource

    private(set) var challenge: ParentGateChallenge
    private(set) var failedAttempts: Int = 0
    var input: String = ""
    private(set) var didPass: Bool = false

    init(random: RandomSource = SystemRandomSource()) {
        self.random = random
        self.challenge = ParentGate.makeChallenge(random: random)
    }

    var questionText: String { challenge.questionText }

    func append(digit: Int) {
        guard input.count < 3 else { return }
        input += "\(digit)"
    }

    func clear() {
        input = ""
    }

    @discardableResult
    func submit() -> Bool {
        guard let value = Int(input) else {
            regenerate()
            return false
        }
        if challenge.isCorrect(value) {
            didPass = true
            return true
        }
        failedAttempts += 1
        regenerate()
        return false
    }

    private func regenerate() {
        input = ""
        challenge = ParentGate.makeChallenge(random: random)
    }

    func reset() {
        didPass = false
        failedAttempts = 0
        regenerate()
    }
}

/// 保護者向けの設定画面。
@MainActor
@Observable
final class SettingsViewModel {
    private let environment: AppEnvironment

    var draft: AppSettings
    var childName: String
    var childAge: Int
    var buddyCharacterID: String
    /// 写真を取り込めなかったときに出す一言。
    var avatarError: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.draft = environment.settings
        self.childName = environment.profile?.nickname ?? ""
        self.childAge = environment.profile?.age ?? 4
        self.buddyCharacterID = environment.profile?.buddyCharacterID ?? CharacterCatalog.defaultCharacterID
    }

    var availableCharacters: [CharacterDefinition] {
        environment.availableCharacters
    }

    var mealDurationPresets: [Int] { AppSettings.mealDurationPresets }

    /// 変更を保存する。画面を閉じるとき・値が変わるたびに呼ぶ。
    func apply() {
        environment.update(settings: draft)
        let profile = ChildProfile(
            id: environment.profile?.id ?? UUID(),
            nickname: childName,
            age: childAge,
            buddyCharacterID: buddyCharacterID,
            // アイコンはこの画面の別の操作で決めるので、いまの設定を引き継ぐ。
            avatar: environment.profile?.avatar,
            createdAt: environment.profile?.createdAt ?? environment.clock.now
        )
        environment.save(profile: profile)
    }

    // MARK: - アプリの呼び名

    /// いま画面に出ている名前。
    var appDisplayName: String { AppNaming.displayName(custom: draft.appDisplayName) }

    /// 子どもの名前から作る候補。いまの名前と同じなら出さない。
    var appNameSuggestion: String? {
        let profile = ChildProfile(nickname: childName, age: childAge)
        guard let suggestion = AppNaming.suggestion(for: profile) else { return nil }
        return suggestion == AppNaming.sanitize(draft.appDisplayName) ? nil : suggestion
    }

    var isUsingDefaultAppName: Bool {
        AppNaming.sanitize(draft.appDisplayName).isEmpty
    }

    func useSuggestedAppName() {
        guard let suggestion = appNameSuggestion else { return }
        draft.appDisplayName = suggestion
        apply()
    }

    func resetAppName() {
        draft.appDisplayName = ""
        apply()
    }

    // MARK: - じぶんの アイコン

    var avatar: ProfileAvatar { environment.avatar }

    var avatarPhotoData: Data? { environment.avatarImageData() }

    var isUsingPhotoAvatar: Bool { environment.avatar.photoFileName != nil }

    /// 写真を取り込む。整えた JPEG だけを端末に保存する。
    func useAvatarPhoto(data: Data?) {
        guard let data, !data.isEmpty else {
            avatarError = "しゃしんを よみこめませんでした"
            return
        }
        guard environment.updateAvatarPhoto(data: data) else {
            avatarError = "しゃしんを ほぞんできませんでした"
            return
        }
        avatarError = nil
    }

    /// 写真をやめて、あいぼうの絵に戻す。
    func useCharacterAvatar() {
        environment.updateAvatar(characterID: buddyCharacterID)
        avatarError = nil
    }

    func toggle(subject: Subject) {
        var subjects = draft.enabledSubjects
        if subjects.contains(subject) {
            // 最後の 1 つは外せないようにする（学習が空にならないため）。
            guard subjects.count > 1 else { return }
            subjects.remove(subject)
        } else {
            subjects.insert(subject)
        }
        draft.enabledSubjects = subjects
        apply()
    }

    func isEnabled(subject: Subject) -> Bool {
        draft.enabledSubjects.contains(subject)
    }
}

/// 保護者向けの習熟度画面。
@MainActor
@Observable
final class ParentDashboardViewModel {
    private let environment: AppEnvironment

    private(set) var summary: ProgressSummary = .empty
    /// 文字・数字ごとの習熟度。キーは `ItemMastery.id`。
    private(set) var itemMastery: [String: ItemMastery] = [:]
    /// 習熟度に算入しないなぞり書きの回数。
    private(set) var practiceCounts: [LearningItemID: Int] = [:]

    private let itemEstimator = ItemMasteryEstimator()

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func refresh() {
        environment.refreshProgress()
        summary = environment.progress

        let attempts = environment.historyStore.attempts()
        itemMastery = itemEstimator.snapshots(from: attempts)
        practiceCounts = itemEstimator.practiceCounts(from: attempts)
    }

    // MARK: - 文字・数字ごとの習熟度

    func mastery(for item: LearningItemID, ability: LearningAbility) -> ItemMastery? {
        itemMastery["\(item.rawValue).\(ability.rawValue)"]
    }

    func averagePercent(for category: LearningItemID.Category, ability: LearningAbility) -> Int? {
        itemEstimator.averagePercent(for: category, ability: ability, in: itemMastery)
    }

    func practiceCount(for item: LearningItemID) -> Int {
        practiceCounts[item] ?? 0
    }

    /// そのカテゴリで追いかける項目の並び。
    func items(in category: LearningItemID.Category) -> [LearningItemID] {
        switch category {
        case .hiragana:
            return KanaCatalog.all.map { .kana($0.hiragana, subject: .hiragana) }
        case .katakana:
            return KanaCatalog.all.map { .kana($0.katakana, subject: .katakana) }
        case .alphabet:
            return AlphabetCatalog.all.map { .alphabet($0.uppercase) }
        case .number:
            return (0 ... 9).map { .number($0) }
        }
    }

    /// そのカテゴリで見せる力。数字に「かき」の問題は無い。
    func abilities(in category: LearningItemID.Category) -> [LearningAbility] {
        category == .number ? [.read] : [.read, .write]
    }

    var childName: String {
        environment.profile?.nickname ?? "おこさま"
    }

    /// 直近 7 日のグラフ用データ。
    var weeklyStats: [DailyStat] {
        summary.dailyStats
    }

    var maximumDailyQuestions: Int {
        max(1, weeklyStats.map(\.questionCount).max() ?? 1)
    }

    var accuracyText: String {
        guard let accuracy = summary.overallAccuracy else { return "—" }
        return "\(Int((accuracy * 100).rounded()))%"
    }

    var totalStudyMinutes: Int {
        Int((summary.totalStudySeconds / 60).rounded())
    }

    func formattedDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = .piyo
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = .piyo
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }
}
