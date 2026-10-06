import Foundation

/// ご飯タイマーの設定。
public struct MealRaceConfiguration: Equatable, Sendable {
    /// 保護者が設定した食事時間（秒）
    public let targetDuration: TimeInterval
    public let characterID: String
    /// 毎回まったく同じにならないようにするためのシード
    public let seed: UInt64

    public init(targetDuration: TimeInterval, characterID: String, seed: UInt64) {
        self.targetDuration = max(60, targetDuration)
        self.characterID = characterID
        self.seed = seed
    }

    public init(settings: AppSettings, seed: UInt64) {
        self.init(
            targetDuration: settings.mealDuration,
            characterID: settings.mealCharacterID,
            seed: seed
        )
    }
}

/// キャラクターの今の様子。
public enum CharacterActivity: String, Equatable, Sendable {
    case eating
    case resting
    case cheering
    case finished

    public var childCaption: String {
        switch self {
        case .eating: return "もぐもぐ"
        case .resting: return "ひとやすみ"
        case .cheering: return "おうえんちゅう"
        case .finished: return "ごちそうさま！"
        }
    }
}

/// どちらがリードしているか。
public enum RaceLeader: String, Equatable, Sendable {
    case child
    case character
    case even
}

/// キャラクターの食事ペースを構成する 1 区間。
public struct PaceSegment: Equatable, Sendable {
    public let activity: CharacterActivity
    public let duration: TimeInterval
    /// この区間で進む食事の割合（0.0 - 1.0）
    public let progressDelta: Double

    public init(activity: CharacterActivity, duration: TimeInterval, progressDelta: Double) {
        self.activity = activity
        self.duration = max(0, duration)
        self.progressDelta = max(0, progressDelta)
    }
}

/// キャラクターの食事計画。一定速度ではなく、食べる・休む・応援するを織り交ぜる。
public struct CharacterPacePlan: Equatable, Sendable {
    public let segments: [PaceSegment]
    /// キャラクターが食べ終わる時刻（秒）
    public let finishTime: TimeInterval

    public init(segments: [PaceSegment], finishTime: TimeInterval) {
        self.segments = segments
        self.finishTime = max(1, finishTime)
    }

    /// 経過時間における食事の進捗（0.0 - 1.0）。
    public func progress(at elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        if elapsed >= finishTime { return 1 }

        var remaining = elapsed
        var progress = 0.0
        for segment in segments {
            if remaining <= 0 { break }
            if remaining >= segment.duration {
                progress += segment.progressDelta
                remaining -= segment.duration
            } else {
                let ratio = segment.duration > 0 ? remaining / segment.duration : 1
                progress += segment.progressDelta * ratio
                remaining = 0
            }
        }
        return min(1, max(0, progress))
    }

    /// 経過時間におけるキャラクターの様子。
    public func activity(at elapsed: TimeInterval) -> CharacterActivity {
        if elapsed >= finishTime { return .finished }
        var remaining = elapsed
        for segment in segments {
            if remaining < segment.duration {
                return segment.activity
            }
            remaining -= segment.duration
        }
        return .finished
    }

    /// 計画全体の長さ。
    public var totalDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    /// 進捗の合計（1.0 になるはず）。
    public var totalProgress: Double {
        segments.reduce(0) { $0 + $1.progressDelta }
    }
}

/// 実行中のスナップショット。
public struct MealRaceSnapshot: Equatable, Sendable {
    public let elapsed: TimeInterval
    public let childProgress: Double
    public let characterProgress: Double
    public let characterActivity: CharacterActivity
    public let leader: RaceLeader
    /// 設定時間までの残り秒（マイナスにはしない）
    public let remainingToTarget: TimeInterval

    public init(
        elapsed: TimeInterval,
        childProgress: Double,
        characterProgress: Double,
        characterActivity: CharacterActivity,
        leader: RaceLeader,
        remainingToTarget: TimeInterval
    ) {
        self.elapsed = elapsed
        self.childProgress = childProgress
        self.characterProgress = characterProgress
        self.characterActivity = characterActivity
        self.leader = leader
        self.remainingToTarget = remainingToTarget
    }

    public var characterHasFinished: Bool { characterProgress >= 1.0 }
}

/// レース結果。ネガティブな表現は一切含めない。
public struct MealRaceResult: Equatable, Sendable {
    public let childFinishedFirst: Bool
    public let elapsed: TimeInterval
    public let characterFinishTime: TimeInterval
    public let starsEarned: Int
    public let headline: String
    public let subline: String

    public init(
        childFinishedFirst: Bool,
        elapsed: TimeInterval,
        characterFinishTime: TimeInterval,
        starsEarned: Int,
        headline: String,
        subline: String
    ) {
        self.childFinishedFirst = childFinishedFirst
        self.elapsed = elapsed
        self.characterFinishTime = characterFinishTime
        self.starsEarned = starsEarned
        self.headline = headline
        self.subline = subline
    }
}

/// ご飯タイマーの進行ロジック。
public struct MealRaceEngine {
    public let configuration: MealRaceConfiguration
    public let character: CharacterDefinition
    public let plan: CharacterPacePlan

    /// 「もぐもぐ」1 回で進む割合
    public static let biteProgress: Double = 0.015
    /// タップで稼げる進捗の上限
    public static let maximumBiteBonus: Double = 0.22
    /// 子どもの進捗は 1.0 手前で止め、「たべおわった！」ボタンで完了させる
    public static let childProgressCeiling: Double = 0.96

    public init(configuration: MealRaceConfiguration) {
        self.configuration = configuration
        self.character = CharacterCatalog.character(id: configuration.characterID) ?? CharacterCatalog.fallback
        self.plan = MealRaceEngine.makePlan(
            targetDuration: configuration.targetDuration,
            personality: character.personality,
            seed: configuration.seed
        )
    }

    // MARK: - 計画づくり

    /// キャラクターがゴールする時刻を決める。設定時間を基準に、毎回すこしだけ変える。
    public static func characterFinishTime(
        targetDuration: TimeInterval,
        personality: CharacterPersonality,
        random: RandomSource
    ) -> TimeInterval {
        // ばらつきの幅は性格によって 4% 〜 12%
        let spread = 0.04 + 0.08 * personality.paceVariance
        let jitter = 1.0 + (random.nextDouble() * 2 - 1) * spread
        let clamped = min(max(jitter, 0.85), 1.12)
        return targetDuration * clamped
    }

    /// 寝る（ひとやすみ）1 回の長さ。
    public static let restDurationRange: ClosedRange<TimeInterval> = 50 ... 70
    /// 応援 1 回の長さ。
    public static let cheerDurationRange: ClosedRange<TimeInterval> = 5 ... 16

    /// 食べる・休む・応援するを織り交ぜたペース計画をつくる。
    public static func makePlan(
        targetDuration: TimeInterval,
        personality: CharacterPersonality,
        seed: UInt64
    ) -> CharacterPacePlan {
        let random = SeededRandomSource(seed: seed)
        let finishTime = characterFinishTime(
            targetDuration: targetDuration,
            personality: personality,
            random: random
        )

        // だいたい 50 秒にひとつの「食べる区間」をつくる。
        let eatingSegmentCount = max(3, min(12, Int(finishTime / 50)))

        // 休憩・応援の区間数と長さ
        var breakCount = Int((Double(eatingSegmentCount - 1) * (0.4 + 0.6 * personality.restTendency)).rounded())
        breakCount = max(1, min(eatingSegmentCount - 1, breakCount))

        // 休憩ごとに「寝る（ひとやすみ）」か「応援」かを先に決める。
        // 寝るときは 1 分くらいしっかり寝る。短いと、目を閉じたと思ったらすぐ起きて落ち着かない。
        var breakIsCheer: [Bool] = []
        var breakDurations: [TimeInterval] = []
        for _ in 0 ..< breakCount {
            let isCheer = random.nextDouble() < personality.cheerTendency
            breakIsCheer.append(isCheer)
            breakDurations.append(isCheer
                ? random.nextDouble(in: cheerDurationRange)
                : random.nextDouble(in: restDurationRange))
        }
        // 休憩の合計は食事時間の 35% まで。超えるなら、寝る回を後ろから短い応援に替えて収める。
        let breakLimit = finishTime * 0.35
        var restIndex = breakIsCheer.lastIndex(of: false)
        while breakDurations.reduce(0, +) > breakLimit, let index = restIndex {
            breakIsCheer[index] = true
            breakDurations[index] = random.nextDouble(in: cheerDurationRange)
            restIndex = breakIsCheer[..<index].lastIndex(of: false)
        }
        let totalBreak = min(breakDurations.reduce(0, +), breakLimit)
        // それでも超える場合は比率を保って縮める。
        let breakScale = breakDurations.reduce(0, +) > 0 ? totalBreak / breakDurations.reduce(0, +) : 0
        breakDurations = breakDurations.map { $0 * breakScale }

        let eatingTime = max(1, finishTime - totalBreak)

        // 食べる量の配分（気まぐれなほど偏る）
        var weights: [Double] = []
        for _ in 0 ..< eatingSegmentCount {
            let base = 1.0
            let variance = personality.paceVariance
            weights.append(base + (random.nextDouble() * 2 - 1) * variance * 0.8)
        }
        let weightSum = weights.reduce(0, +)
        let normalized = weightSum > 0
            ? weights.map { $0 / weightSum }
            : [Double](repeating: 1.0 / Double(eatingSegmentCount), count: eatingSegmentCount)

        var segments: [PaceSegment] = []
        var breakIndex = 0
        for index in 0 ..< eatingSegmentCount {
            segments.append(
                PaceSegment(
                    activity: .eating,
                    duration: eatingTime * normalized[index],
                    progressDelta: normalized[index]
                )
            )
            if breakIndex < breakDurations.count, index < eatingSegmentCount - 1 {
                // 応援しやすい性格ほど、休憩が「おうえん」になる。
                let isCheer = breakIsCheer[breakIndex]
                segments.append(
                    PaceSegment(
                        activity: isCheer ? .cheering : .resting,
                        duration: breakDurations[breakIndex],
                        progressDelta: 0
                    )
                )
                breakIndex += 1
            }
        }

        return CharacterPacePlan(segments: segments, finishTime: finishTime)
    }

    // MARK: - 進行

    /// 子どもの進捗。経過時間のペースに、「もぐもぐ」タップのボーナスを足す。
    public func childProgress(elapsed: TimeInterval, bites: Int) -> Double {
        let paced = elapsed / configuration.targetDuration
        let bonus = min(MealRaceEngine.maximumBiteBonus, Double(max(0, bites)) * MealRaceEngine.biteProgress)
        return min(MealRaceEngine.childProgressCeiling, max(0, paced + bonus))
    }

    /// 現在の状況。
    public func snapshot(at elapsed: TimeInterval, bites: Int = 0) -> MealRaceSnapshot {
        let childValue = childProgress(elapsed: elapsed, bites: bites)
        let characterValue = plan.progress(at: elapsed)
        let leader: RaceLeader
        if abs(childValue - characterValue) < 0.03 {
            leader = .even
        } else {
            leader = childValue > characterValue ? .child : .character
        }
        return MealRaceSnapshot(
            elapsed: elapsed,
            childProgress: childValue,
            characterProgress: characterValue,
            characterActivity: plan.activity(at: elapsed),
            leader: leader,
            remainingToTarget: max(0, configuration.targetDuration - elapsed)
        )
    }

    /// キャラクターが食べ終わったか。
    public func hasCharacterFinished(at elapsed: TimeInterval) -> Bool {
        elapsed >= plan.finishTime
    }

    /// 「たべおわった！」が押されたときの結果。
    public func finish(at elapsed: TimeInterval, childName: String) -> MealRaceResult {
        let childFirst = elapsed < plan.finishTime
        let headline: String
        let subline: String
        if childFirst {
            headline = "やったー！"
            subline = character.childWonLine(childName: childName)
        } else {
            // キャラクターが先でも、応援と一緒に喜ぶ表現だけを使う。
            headline = "ごちそうさま！"
            subline = character.finishTogetherLine(childName: childName)
        }
        return MealRaceResult(
            childFinishedFirst: childFirst,
            elapsed: elapsed,
            characterFinishTime: plan.finishTime,
            starsEarned: childFirst ? 3 : 2,
            headline: headline,
            subline: subline
        )
    }

    /// 進行中にキャラクターが出すことば。
    public func message(at elapsed: TimeInterval, childName: String) -> String {
        if hasCharacterFinished(at: elapsed) {
            return character.characterFinishedLine
        }
        switch plan.activity(at: elapsed) {
        case .eating: return character.eatLine
        case .resting: return character.restLine
        case .cheering: return character.cheerLine(childName: childName)
        case .finished: return character.characterFinishedLine
        }
    }
}
