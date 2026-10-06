import Foundation

/// 文字・数字ひとつ分の習熟度（よみ / かき 別）。
public struct ItemMastery: Equatable, Sendable, Identifiable {
    public let itemID: LearningItemID
    public let ability: LearningAbility
    /// 習熟度に算入した回答数（聞き取れなかったものは含まない）
    public var attempts: Int
    public var correctCount: Int
    /// 直近を重く見た習熟度（0.0 - 1.0）
    public var ewma: Double
    public var lastPracticedAt: Date?

    public var id: String { "\(itemID.rawValue).\(ability.rawValue)" }

    /// 画面に出すパーセント。
    public var percent: Int { Int((min(max(ewma, 0), 1) * 100).rounded()) }

    /// 全期間の正答率。まだ解いていなければ nil。
    public var accuracy: Double? {
        attempts == 0 ? nil : Double(correctCount) / Double(attempts)
    }

    public init(
        itemID: LearningItemID,
        ability: LearningAbility,
        attempts: Int = 0,
        correctCount: Int = 0,
        ewma: Double = 0,
        lastPracticedAt: Date? = nil
    ) {
        self.itemID = itemID
        self.ability = ability
        self.attempts = attempts
        self.correctCount = correctCount
        self.ewma = ewma
        self.lastPracticedAt = lastPracticedAt
    }
}

/// 回答履歴から、文字・数字ごとの習熟度を積み上げる。
///
/// 1 文字あたりの出題数は多くないので、Skill 単位より係数を大きくして
/// 「今日やったこと」が反映されやすいようにしている。
public struct ItemMasteryEstimator {
    public let alpha: Double

    public init(alpha: Double = 0.4) {
        self.alpha = min(max(alpha, 0.01), 1.0)
    }

    /// 項目 × よみ/かき ごとの習熟度。キーは `ItemMastery.id`。
    public func snapshots(from attempts: [AttemptRecord]) -> [String: ItemMastery] {
        var result: [String: ItemMastery] = [:]
        for attempt in attempts.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let itemID = attempt.itemID, let ability = attempt.ability else { continue }
            let key = "\(itemID.rawValue).\(ability.rawValue)"
            var mastery = result[key] ?? ItemMastery(itemID: itemID, ability: ability)
            mastery.lastPracticedAt = attempt.createdAt

            guard attempt.judgement.countsTowardMastery else {
                result[key] = mastery
                continue
            }

            let outcome = attempt.judgement.isCorrect ? 1.0 : 0.0
            // 1 回目は平均を取らずそのまま入れる。0 から始めると
            // 「1 回で正解したのに 40%」のような表示になってしまう。
            mastery.ewma = mastery.attempts == 0
                ? outcome
                : mastery.ewma * (1 - alpha) + outcome * alpha
            mastery.attempts += 1
            if attempt.judgement.isCorrect {
                mastery.correctCount += 1
            }
            result[key] = mastery
        }
        return result
    }

    /// 習熟度には算入しない練習（なぞり書き）の回数。
    public func practiceCounts(from attempts: [AttemptRecord]) -> [LearningItemID: Int] {
        var result: [LearningItemID: Int] = [:]
        for attempt in attempts where attempt.ability == nil {
            guard let itemID = attempt.itemID else { continue }
            result[itemID, default: 0] += 1
        }
        return result
    }

    /// カテゴリ全体の平均習熟度（やった項目だけの平均）。まだ何もなければ nil。
    public func averagePercent(
        for category: LearningItemID.Category,
        ability: LearningAbility,
        in snapshots: [String: ItemMastery]
    ) -> Int? {
        let relevant = snapshots.values.filter {
            $0.itemID.category == category && $0.ability == ability && $0.attempts > 0
        }
        guard !relevant.isEmpty else { return nil }
        let total = relevant.reduce(0.0) { $0 + $1.ewma }
        return Int((total / Double(relevant.count) * 100).rounded())
    }
}
