import Foundation

/// 1 回の学習を保護者向けに振り返る。
///
/// 記録しているのは「何の Skill を・何回目の挑戦で・どう答えたか」なので、
/// 問題文そのものは出せない。代わりに、どこが得意でどこに時間がかかったかを示し、
/// 声をかけるきっかけになる「ほめポイント」を組み立てる。
public struct SessionReview: Equatable, Sendable {

    /// Skill ごとの結果。
    public struct SkillOutcome: Equatable, Sendable, Identifiable {
        public let skill: Skill
        /// 出題数
        public let questionCount: Int
        /// 1 回目で正解した数
        public let solvedOnFirstTry: Int
        /// やり直して正解した数
        public let solvedAfterRetry: Int
        /// 最後まで正解にならなかった数
        public let unsolved: Int

        public var id: String { skill.rawValue }
        public var solved: Int { solvedOnFirstTry + solvedAfterRetry }

        public init(
            skill: Skill,
            questionCount: Int,
            solvedOnFirstTry: Int,
            solvedAfterRetry: Int,
            unsolved: Int
        ) {
            self.skill = skill
            self.questionCount = questionCount
            self.solvedOnFirstTry = solvedOnFirstTry
            self.solvedAfterRetry = solvedAfterRetry
            self.unsolved = unsolved
        }
    }

    public let outcomes: [SkillOutcome]
    /// 保護者に見せる「ほめポイント」。多すぎると読まれないので絞る。
    public let praisePoints: [String]
    /// つまずいたところ。責める言い方にはしない。
    public let watchPoints: [String]

    public init(outcomes: [SkillOutcome], praisePoints: [String], watchPoints: [String]) {
        self.outcomes = outcomes
        self.praisePoints = praisePoints
        self.watchPoints = watchPoints
    }

    public var isEmpty: Bool { outcomes.isEmpty }

    // MARK: - 組み立て

    /// ほめポイントの最大数。
    public static let maximumPraisePoints = 3

    public static func make(from summary: SessionSummary) -> SessionReview {
        let questions = groupIntoQuestions(summary.attempts)
        guard !questions.isEmpty else {
            return SessionReview(outcomes: [], praisePoints: [], watchPoints: [])
        }

        var outcomes: [Skill: SkillOutcome] = [:]
        for question in questions {
            guard let skill = question.first?.skill else { continue }
            let existing = outcomes[skill]
            let solvedFirst = question.count == 1 && question[0].judgement == .correct
            let solvedLater = question.count > 1 && question.contains { $0.judgement == .correct }
            let unsolved = !question.contains { $0.judgement == .correct }
            outcomes[skill] = SkillOutcome(
                skill: skill,
                questionCount: (existing?.questionCount ?? 0) + 1,
                solvedOnFirstTry: (existing?.solvedOnFirstTry ?? 0) + (solvedFirst ? 1 : 0),
                solvedAfterRetry: (existing?.solvedAfterRetry ?? 0) + (solvedLater ? 1 : 0),
                unsolved: (existing?.unsolved ?? 0) + (unsolved ? 1 : 0)
            )
        }

        let ordered = outcomes.values.sorted { lhs, rhs in
            if lhs.skill.subject.learningPriority != rhs.skill.subject.learningPriority {
                return lhs.skill.subject.learningPriority < rhs.skill.subject.learningPriority
            }
            return lhs.skill.rawValue < rhs.skill.rawValue
        }

        return SessionReview(
            outcomes: ordered,
            praisePoints: praisePoints(outcomes: ordered, attempts: summary.attempts, summary: summary),
            watchPoints: watchPoints(outcomes: ordered)
        )
    }

    /// attempt の並びを問題ごとに切り分ける。
    /// 1 問目の挑戦は attemptIndex == 1 なので、そこが問題の切れ目になる。
    static func groupIntoQuestions(_ attempts: [AttemptRecord]) -> [[AttemptRecord]] {
        var questions: [[AttemptRecord]] = []
        for attempt in attempts.sorted(by: { $0.createdAt < $1.createdAt }) {
            if attempt.attemptIndex <= 1 || questions.isEmpty {
                questions.append([attempt])
            } else {
                questions[questions.count - 1].append(attempt)
            }
        }
        return questions
    }

    private static func praisePoints(
        outcomes: [SkillOutcome],
        attempts: [AttemptRecord],
        summary: SessionSummary
    ) -> [String] {
        var points: [String] = []

        // 一度で解けたものは、具体的に名前を挙げて伝える。
        let confident = outcomes
            .filter { $0.solvedOnFirstTry > 0 }
            .sorted { $0.solvedOnFirstTry > $1.solvedOnFirstTry }
        if let best = confident.first {
            points.append("「\(best.skill.parentTitle)」を \(best.solvedOnFirstTry)問、一度で正解しました。"
                + "「\(best.skill.childTitle)、すぐ わかったね」と声をかけてみてください。")
        }

        // やり直して正解したときは、粘れたこと自体をほめてもらう。
        let persisted = outcomes.reduce(0) { $0 + $1.solvedAfterRetry }
        if persisted > 0 {
            points.append("まちがえたあとに もう一度挑戦して \(persisted)問 正解しました。"
                + "「あきらめないで できたね」と粘り強さをほめてあげてください。")
        }

        // 手や声を使った回答は、それ自体が挑戦なので拾う。
        if attempts.contains(where: { $0.answerMode == .trace }) {
            points.append("文字をなぞる練習をしました。「ゆっくり ていねいに かけたね」と形を見てあげてください。")
        } else if attempts.contains(where: { $0.answerMode == .voice }) {
            points.append("声に出して答えました。「はっきり いえたね」と伝えてあげてください。")
        }

        if points.isEmpty, summary.questionCount > 0 {
            points.append("最後まで \(summary.questionCount)問 取り組みました。"
                + "「さいごまで やったね」と続けられたことをほめてあげてください。")
        }

        return Array(points.prefix(maximumPraisePoints))
    }

    private static func watchPoints(outcomes: [SkillOutcome]) -> [String] {
        outcomes
            .filter { $0.unsolved > 0 }
            .map { outcome in
                "「\(outcome.skill.parentTitle)」は まだむずかしいようです。"
                    + "いっしょに ゆっくり やってみると 進みやすくなります。"
            }
    }
}
