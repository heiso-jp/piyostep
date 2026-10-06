import Foundation

/// 習熟度を「文字」「数字」といった項目ごとに追うための ID。
///
/// Skill 単位（ひらがなの読み、など）より細かく、「あ」「7」といった 1 つ 1 つを指す。
/// 保存には `rawValue`（例 `"hiragana.あ"`）を使う。
public struct LearningItemID: Hashable, Codable, Sendable, Identifiable {

    public enum Category: String, Codable, Sendable, CaseIterable {
        case hiragana
        case katakana
        case alphabet
        case number

        public var parentTitle: String {
            switch self {
            case .hiragana: return "ひらがな"
            case .katakana: return "カタカナ"
            case .alphabet: return "アルファベット"
            case .number: return "数字"
            }
        }
    }

    public let category: Category
    /// カテゴリの中での識別子。文字そのもの（"あ"）や数字（"7"）。
    public let value: String

    public var id: String { rawValue }
    public var rawValue: String { "\(category.rawValue).\(value)" }

    public init(category: Category, value: String) {
        self.category = category
        self.value = value
    }

    /// 保存された文字列から戻す。形式が違えば nil。
    public init?(rawValue: String) {
        guard let separator = rawValue.firstIndex(of: ".") else { return nil }
        let head = String(rawValue[rawValue.startIndex ..< separator])
        let tail = String(rawValue[rawValue.index(after: separator)...])
        guard let category = Category(rawValue: head), !tail.isEmpty else { return nil }
        self.init(category: category, value: tail)
    }

    // MARK: - つくるときのショートカット

    public static func kana(_ character: String, subject: Subject) -> LearningItemID {
        LearningItemID(category: subject == .katakana ? .katakana : .hiragana, value: character)
    }

    public static func alphabet(_ letter: String) -> LearningItemID {
        LearningItemID(category: .alphabet, value: letter.uppercased())
    }

    public static func number(_ value: Int) -> LearningItemID {
        LearningItemID(category: .number, value: String(value))
    }
}

/// 項目に対する「なに ができるか」。
///
/// 読みと書きは別々に積み上げる。「あ は読めるが書けない」を見分けたいため。
public enum LearningAbility: String, Codable, Sendable, CaseIterable {
    case read
    case write

    public var parentTitle: String {
        switch self {
        case .read: return "よみ"
        case .write: return "かき"
        }
    }
}
