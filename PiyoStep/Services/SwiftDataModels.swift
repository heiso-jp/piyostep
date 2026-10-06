import Foundation
import SwiftData
import PiyoCore

// MARK: - 永続化エンティティ
//
// 将来 iCloud 同期（CloudKit）へ移行できるよう、
// ・すべてのプロパティにデフォルト値を持たせる
// ・リレーションを張らず ID 参照にする
// という方針で定義している。

@Model
final class AttemptEntity {
    var identifier: UUID = UUID()
    var sessionIdentifier: UUID?
    var skillRaw: String = Skill.numberCount.rawValue
    var difficultyRaw: Int = 1
    var judgementRaw: String = AnswerJudgement.correct.rawValue
    var answerModeRaw: String = AnswerMode.choice.rawValue
    var attemptIndex: Int = 1
    var duration: Double = 0
    var createdAt: Date = Date()
    /// 項目ごとの習熟度に使う。古いデータには入っていないので省略可能。
    var itemIDRaw: String?
    var abilityRaw: String?

    init(record: AttemptRecord) {
        self.identifier = record.id
        self.sessionIdentifier = record.sessionID
        self.skillRaw = record.skill.rawValue
        self.difficultyRaw = record.difficulty.raw
        self.judgementRaw = record.judgement.rawValue
        self.answerModeRaw = record.answerMode.rawValue
        self.attemptIndex = record.attemptIndex
        self.duration = record.duration
        self.createdAt = record.createdAt
        self.itemIDRaw = record.itemID?.rawValue
        self.abilityRaw = record.ability?.rawValue
    }

    var record: AttemptRecord? {
        guard let skill = Skill(rawValue: skillRaw),
              let judgement = AnswerJudgement(rawValue: judgementRaw),
              let mode = AnswerMode(rawValue: answerModeRaw) else { return nil }
        return AttemptRecord(
            id: identifier,
            sessionID: sessionIdentifier,
            skill: skill,
            difficulty: DifficultyLevel(difficultyRaw),
            judgement: judgement,
            answerMode: mode,
            attemptIndex: attemptIndex,
            duration: duration,
            createdAt: createdAt,
            itemID: itemIDRaw.flatMap(LearningItemID.init(rawValue:)),
            ability: abilityRaw.flatMap(LearningAbility.init(rawValue:))
        )
    }
}

@Model
final class SessionEntity {
    var identifier: UUID = UUID()
    var kindRaw: String = SessionKind.dailyChallenge.rawValue
    var subjectRaw: String?
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    var questionCount: Int = 0
    var correctCount: Int = 0
    var starsEarned: Int = 0

    init(record: SessionRecord) {
        self.identifier = record.id
        self.kindRaw = record.kind.rawValue
        self.subjectRaw = record.subject?.rawValue
        self.startedAt = record.startedAt
        self.endedAt = record.endedAt
        self.questionCount = record.questionCount
        self.correctCount = record.correctCount
        self.starsEarned = record.starsEarned
    }

    var record: SessionRecord? {
        guard let kind = SessionKind(rawValue: kindRaw) else { return nil }
        return SessionRecord(
            id: identifier,
            kind: kind,
            subject: subjectRaw.flatMap { Subject(rawValue: $0) },
            startedAt: startedAt,
            endedAt: endedAt,
            questionCount: questionCount,
            correctCount: correctCount,
            starsEarned: starsEarned
        )
    }
}

@Model
final class MealSessionEntity {
    var identifier: UUID = UUID()
    var characterID: String = CharacterCatalog.defaultCharacterID
    var targetDuration: Double = 900
    var actualDuration: Double = 0
    var childFinishedFirst: Bool = false
    var startedAt: Date = Date()

    init(record: MealSessionRecord) {
        self.identifier = record.id
        self.characterID = record.characterID
        self.targetDuration = record.targetDuration
        self.actualDuration = record.actualDuration
        self.childFinishedFirst = record.childFinishedFirst
        self.startedAt = record.startedAt
    }

    var record: MealSessionRecord {
        MealSessionRecord(
            id: identifier,
            characterID: characterID,
            targetDuration: targetDuration,
            actualDuration: actualDuration,
            childFinishedFirst: childFinishedFirst,
            startedAt: startedAt
        )
    }
}

@Model
final class MasteryEntity {
    var skillRaw: String = Skill.numberCount.rawValue
    var ewma: Double = MasterySnapshot.initialEWMA
    var attempts: Int = 0
    var correctCount: Int = 0
    var levelRaw: Int = 1
    var attemptsAtCurrentLevel: Int = 0
    var lastPracticedAt: Date?

    init(snapshot: MasterySnapshot) {
        self.skillRaw = snapshot.skill.rawValue
        self.ewma = snapshot.ewma
        self.attempts = snapshot.attempts
        self.correctCount = snapshot.correctCount
        self.levelRaw = snapshot.level.raw
        self.attemptsAtCurrentLevel = snapshot.attemptsAtCurrentLevel
        self.lastPracticedAt = snapshot.lastPracticedAt
    }

    func apply(_ snapshot: MasterySnapshot) {
        self.ewma = snapshot.ewma
        self.attempts = snapshot.attempts
        self.correctCount = snapshot.correctCount
        self.levelRaw = snapshot.level.raw
        self.attemptsAtCurrentLevel = snapshot.attemptsAtCurrentLevel
        self.lastPracticedAt = snapshot.lastPracticedAt
    }

    var snapshot: MasterySnapshot? {
        guard let skill = Skill(rawValue: skillRaw) else { return nil }
        return MasterySnapshot(
            skill: skill,
            ewma: ewma,
            attempts: attempts,
            correctCount: correctCount,
            level: DifficultyLevel(levelRaw),
            attemptsAtCurrentLevel: attemptsAtCurrentLevel,
            lastPracticedAt: lastPracticedAt
        )
    }
}

@Model
final class UnlockEntity {
    var itemID: String = ""
    var unlockedAt: Date = Date()

    init(itemID: String, unlockedAt: Date) {
        self.itemID = itemID
        self.unlockedAt = unlockedAt
    }
}

enum PiyoSchema {
    /// アプリ用のコンテナ。将来 iCloud 同期を足すときはここだけ変更すればよい。
    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: AttemptEntity.self,
            SessionEntity.self,
            MealSessionEntity.self,
            MasteryEntity.self,
            UnlockEntity.self,
            configurations: configuration
        )
    }
}
