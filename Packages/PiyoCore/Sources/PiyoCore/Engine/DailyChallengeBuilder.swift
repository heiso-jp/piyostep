import Foundation

/// 「きょうのチャレンジ」1 回分。
public struct DailyChallenge: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let questions: [Question]

    public init(id: UUID = UUID(), date: Date, questions: [Question]) {
        self.id = id
        self.date = date
        self.questions = questions
    }

    public var skills: [Skill] { questions.map(\.skill) }
    public var subjects: [Subject] {
        Array(Set(questions.map(\.subject))).sorted { $0.learningPriority < $1.learningPriority }
    }
    public var questionCount: Int { questions.count }
}

/// 複数教科から短い問題を組み合わせて「きょうのチャレンジ」をつくる。
public struct DailyChallengeBuilder {
    private let factory: QuestionFactory
    private let difficultyEngine: AdaptiveDifficultyEngine

    public init(
        factory: QuestionFactory = QuestionFactory(),
        difficultyEngine: AdaptiveDifficultyEngine = AdaptiveDifficultyEngine()
    ) {
        self.factory = factory
        self.difficultyEngine = difficultyEngine
    }

    /// 出題候補になる Skill を求める。
    public func availableSkills(profile: ChildProfile, settings: AppSettings) -> [Skill] {
        let enabled = settings.enabledSubjects
        let candidates = Skill.allCases.filter { skill in
            enabled.contains(skill.subject)
                && skill.minimumAge <= profile.age
                && factory.generator(for: skill) != nil
        }
        if !candidates.isEmpty { return candidates }
        // 何も有効になっていない場合でも学習を止めない。
        return Skill.allCases.filter { $0.minimumAge <= profile.age && factory.generator(for: $0) != nil }
    }

    /// Skill の出題優先度。苦手なほど、また久しぶりなほど高い。
    public func weight(
        for skill: Skill,
        snapshot: MasterySnapshot?,
        now: Date
    ) -> Double {
        let base: Double
        if let snapshot {
            let weakness = 1.0 - snapshot.masteryScore
            var recencyBonus = 0.5
            if let last = snapshot.lastPracticedAt {
                let days = now.timeIntervalSince(last) / 86_400
                recencyBonus = min(0.6, max(0.0, days / 7.0 * 0.6))
            }
            base = max(0.05, weakness + recencyBonus)
        } else {
            // 未学習の Skill は積極的に出す。
            base = 1.4
        }
        // 教科ごとの優先度を掛ける。ひらがな・すうじを土台にし、英語系は出過ぎないようにする。
        return base * skill.subject.challengeWeightMultiplier
    }

    /// Skill に対する出題難易度を決める。
    public func level(
        for skill: Skill,
        snapshot: MasterySnapshot?,
        settings: AppSettings,
        profile: ChildProfile,
        recentAttempts: [AttemptRecord]
    ) -> DifficultyLevel {
        let base = snapshot?.level ?? profile.suggestedStartingLevel
        var level = base.clamped(to: settings.difficultyMode.allowedRange)
        if difficultyEngine.needsReview(recentAttempts: recentAttempts, skill: skill) {
            level = difficultyEngine.reviewLevel(for: level, mode: settings.difficultyMode)
        }
        return level
    }

    /// 出題する Skill の並びを決める。
    public func planSkills(
        profile: ChildProfile,
        settings: AppSettings,
        snapshots: [Skill: MasterySnapshot],
        recentAttempts: [AttemptRecord],
        now: Date,
        random: RandomSource
    ) -> [Skill] {
        let pool = availableSkills(profile: profile, settings: settings)
        guard !pool.isEmpty else { return [] }

        let count = settings.dailyGoal.questionCount
        var plan: [Skill] = []

        // 1 問目は「いちばん得意な Skill」。成功体験から始める。
        let warmUp = pool.max { lhs, rhs in
            (snapshots[lhs]?.masteryScore ?? 0) < (snapshots[rhs]?.masteryScore ?? 0)
        } ?? pool[0]
        plan.append(warmUp)

        // 中盤は弱点重視の重み付き抽選。同じ Skill が 3 連続しないようにする。
        while plan.count < max(1, count - 1) {
            let banned = Set(plan.suffix(2))
            let isBlocked = plan.count >= 2 && banned.count == 1
            let candidates = isBlocked ? pool.filter { !banned.contains($0) } : pool
            let source = candidates.isEmpty ? pool : candidates
            let picked = random.pickWeighted(source) { skill in
                weight(for: skill, snapshot: snapshots[skill], now: now)
            } ?? source[0]
            plan.append(picked)
        }

        // 最後は「最近よく遊んだ教科」で気持ちよく終える。
        if plan.count < count {
            var favorite = favoriteSkill(pool: pool, recentAttempts: recentAttempts, random: random)
            // ここでも 3 連続を避ける。
            let tail = Set(plan.suffix(2))
            if plan.count >= 2, tail.count == 1, tail.contains(favorite) {
                let alternatives = pool.filter { $0 != favorite }
                if let replacement = random.pickWeighted(alternatives, weight: { skill in
                    weight(for: skill, snapshot: snapshots[skill], now: now)
                }) {
                    favorite = replacement
                }
            }
            plan.append(favorite)
        }
        return Array(plan.prefix(count))
    }

    /// 直近で最も多く解いた Skill（なければ重み付き抽選）。
    func favoriteSkill(pool: [Skill], recentAttempts: [AttemptRecord], random: RandomSource) -> Skill {
        var counts: [Skill: Int] = [:]
        for attempt in recentAttempts.suffix(50) where pool.contains(attempt.skill) {
            counts[attempt.skill, default: 0] += 1
        }
        if let best = counts.max(by: { $0.value < $1.value })?.key {
            return best
        }
        return random.pick(pool) ?? pool[0]
    }

    /// チャレンジを組み立てる。
    public func build(
        profile: ChildProfile,
        settings: AppSettings,
        snapshots: [Skill: MasterySnapshot],
        recentAttempts: [AttemptRecord] = [],
        now: Date,
        random: RandomSource
    ) -> DailyChallenge {
        let skills = planSkills(
            profile: profile,
            settings: settings,
            snapshots: snapshots,
            recentAttempts: recentAttempts,
            now: now,
            random: random
        )

        var questions: [Question] = []
        for (index, skill) in skills.enumerated() {
            var questionLevel = level(
                for: skill,
                snapshot: snapshots[skill],
                settings: settings,
                profile: profile,
                recentAttempts: recentAttempts
            )
            // 1 問目はウォームアップとして 1 段やさしくする。
            if index == 0 {
                questionLevel = questionLevel.decreased().clamped(to: settings.difficultyMode.allowedRange)
            }
            guard let question = factory.makeQuestion(
                skill: skill,
                level: questionLevel,
                random: random,
                allowVoice: settings.voiceAnswerEnabled
            ) else { continue }
            questions.append(question)
        }

        return DailyChallenge(date: now, questions: questions)
    }
}
