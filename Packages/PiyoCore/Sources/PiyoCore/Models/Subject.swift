import Foundation

/// 教科。ホーム画面のカテゴリと 1 対 1 で対応する。
///
/// case の並びがそのまま学習の優先順位になる。日本語を母語とする子ども向けなので、
/// ひらがな・すうじ を土台に置き、英語系はいちばん後ろに置く。
/// 画面の並び順はここを直せば全部そろう（rawValue は変えないので保存済みデータには影響しない）。
public enum Subject: String, CaseIterable, Codable, Sendable, Identifiable {
    case hiragana
    case number
    case clock
    case katakana
    case alphabet
    case englishWord

    public var id: String { rawValue }

    /// 学習の優先度。小さいほど先に見せる。
    public var learningPriority: Int {
        Subject.allCases.firstIndex(of: self) ?? Subject.allCases.count
    }

    /// 優先度順に並べた教科。ホーム画面や保護者設定の並びに使う。
    public static var orderedByPriority: [Subject] { allCases }

    /// 「きょうのチャレンジ」での出題されやすさの係数。
    /// 母語（ひらがな）と数の土台を優先し、英語系は出過ぎないように抑える。
    public var challengeWeightMultiplier: Double {
        switch self {
        case .hiragana, .number: return 1.0
        case .clock, .katakana: return 0.8
        case .alphabet, .englishWord: return 0.45
        }
    }

    /// 子ども向けのひらがな表記。
    public var childTitle: String {
        switch self {
        case .clock: return "とけい"
        case .hiragana: return "ひらがな"
        case .katakana: return "カタカナ"
        case .number: return "すうじ"
        case .alphabet: return "アルファベット"
        case .englishWord: return "えいごのことば"
        }
    }

    /// 保護者向けの表記。
    public var parentTitle: String {
        switch self {
        case .clock: return "時計"
        case .hiragana: return "ひらがな"
        case .katakana: return "カタカナ"
        case .number: return "数字"
        case .alphabet: return "アルファベット"
        case .englishWord: return "英単語"
        }
    }

    /// この教科に属する Skill。
    public var skills: [Skill] {
        Skill.allCases.filter { $0.subject == self }
    }

    /// 音声認識に使うロケール。
    public var recognitionLocale: RecognitionLocale {
        switch self {
        case .alphabet, .englishWord: return .englishUS
        default: return .japanese
        }
    }
}

/// 習熟度を追跡する最小単位。
public enum Skill: String, CaseIterable, Codable, Sendable, Identifiable {
    case clockRead          // 時計を読む
    case clockSet           // 針を合わせる
    case hiraganaRead       // ひらがなを読む
    case hiraganaWrite      // ひらがなをなぞる/書く
    case hiraganaWord       // ひらがなとことばの対応
    case katakanaRead
    case katakanaWrite
    case katakanaWord
    case numberCount        // 数量と数字の対応
    case numberRead         // 数字を読む
    case placeValue         // 位（一・十・百）
    case alphabetRead
    case alphabetWrite
    case englishWordRead    // 絵 ↔ 英単語

    public var id: String { rawValue }

    public var subject: Subject {
        switch self {
        case .clockRead, .clockSet: return .clock
        case .hiraganaRead, .hiraganaWrite, .hiraganaWord: return .hiragana
        case .katakanaRead, .katakanaWrite, .katakanaWord: return .katakana
        case .numberCount, .numberRead, .placeValue: return .number
        case .alphabetRead, .alphabetWrite: return .alphabet
        case .englishWordRead: return .englishWord
        }
    }

    public var childTitle: String {
        switch self {
        case .clockRead: return "なんじかな？"
        case .clockSet: return "とけいを あわせよう"
        case .hiraganaRead: return "ひらがなを よもう"
        case .hiraganaWrite: return "ひらがなを なぞろう"
        case .hiraganaWord: return "ことばを さがそう"
        case .katakanaRead: return "カタカナを よもう"
        case .katakanaWrite: return "カタカナを なぞろう"
        case .katakanaWord: return "カタカナの ことば"
        case .numberCount: return "いくつ かな？"
        case .numberRead: return "すうじを よもう"
        case .placeValue: return "くらいを みつけよう"
        case .alphabetRead: return "アルファベットを よもう"
        case .alphabetWrite: return "アルファベットを なぞろう"
        case .englishWordRead: return "えいごで いってみよう"
        }
    }

    public var parentTitle: String {
        switch self {
        case .clockRead: return "時刻を読む"
        case .clockSet: return "時計の針を合わせる"
        case .hiraganaRead: return "ひらがなの読み"
        case .hiraganaWrite: return "ひらがなの書き"
        case .hiraganaWord: return "ひらがなと言葉"
        case .katakanaRead: return "カタカナの読み"
        case .katakanaWrite: return "カタカナの書き"
        case .katakanaWord: return "カタカナと言葉"
        case .numberCount: return "数量と数字"
        case .numberRead: return "数字の読み"
        case .placeValue: return "位の概念"
        case .alphabetRead: return "アルファベットの読み"
        case .alphabetWrite: return "アルファベットの書き"
        case .englishWordRead: return "英単語"
        }
    }

    /// なぞり書きなど、音声で答えようのない Skill は false。
    public var supportsVoiceAnswer: Bool {
        switch self {
        case .hiraganaWrite, .katakanaWrite, .alphabetWrite, .clockSet:
            return false
        default:
            return true
        }
    }

    /// 「今日のチャレンジ」で 3 歳児にも出してよいか。
    public var minimumAge: Int {
        switch self {
        case .placeValue: return 5
        case .clockRead, .clockSet: return 4
        case .englishWordRead, .alphabetRead, .alphabetWrite: return 4
        default: return 3
        }
    }
}

/// 音声認識に使う言語。
public enum RecognitionLocale: String, Codable, Sendable {
    case japanese = "ja-JP"
    case englishUS = "en-US"
}
