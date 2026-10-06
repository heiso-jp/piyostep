import Foundation

/// はじめての設定で、子どもの発話から「なまえ」と「ねんれい」を取り出す。
///
/// 「ぼくは ゆうた です」のように名乗ることが多いので、前後の言い回しを落として
/// 名前だけを残す。年齢は「ごさい」「5 さい」どちらでも受け取れるようにする。
public enum SpokenProfileParser {

    /// 名前の前に付きやすい言い回し。長いものから照合する。
    private static let namePrefixes = [
        "わたしのなまえは", "ぼくのなまえは", "わたしのなまえ", "ぼくのなまえ",
        "なまえは", "わたしは", "ぼくは", "おれは", "わたし", "ぼく", "おれ"
    ]

    /// 名前の後ろに付きやすい言い回し。
    private static let nameSuffixes = [
        "といいます", "ていいます", "といいまーす", "でーす", "です",
        "だよー", "だよ", "だもん"
    ]

    /// 名前として残したくない記号・空白。長音「ー」は名前に使うので残す。
    private static let droppedCharacters: Set<Character> = [
        " ", "\u{3000}", "\n", "\t",
        "、", "。", "，", "．", ",", ".", "!", "?", "！", "？",
        "「", "」", "『", "』", "…", "~", "〜"
    ]

    /// 発話から名前を取り出す。名前が残らなければ nil。
    ///
    /// カタカナはひらがなに寄せる（アプリ全体がひらがな表記のため）。
    /// 漢字で認識された場合はそのまま残すので、必要なら保護者が設定で直す。
    public static func name(from transcript: String) -> String? {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        text = JapaneseTextNormalizer.toHalfwidthAlphanumerics(text)
        text = String(text.filter { !droppedCharacters.contains($0) })
        text = JapaneseTextNormalizer.katakanaToHiragana(text)
        text = JapaneseTextNormalizer.stripFillers(text)

        for prefix in namePrefixes where text.hasPrefix(prefix) && text.count > prefix.count {
            text.removeFirst(prefix.count)
            break
        }

        var changed = true
        while changed {
            changed = false
            for suffix in nameSuffixes where text.hasSuffix(suffix) && text.count > suffix.count {
                text.removeLast(suffix.count)
                changed = true
                break
            }
        }

        let cleaned = ChildProfile.sanitize(nickname: text)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// 発話から年齢を取り出す。想定の範囲外や、数として読めないときは nil。
    public static func age(from transcript: String, allowed: ClosedRange<Int> = 3 ... 6) -> Int? {
        guard let value = JapaneseNumberParser.parse(transcript) else { return nil }
        return allowed.contains(value) ? value : nil
    }
}
