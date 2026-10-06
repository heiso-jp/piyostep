import Foundation

/// ごはんタイマー中の声のコマンド。
///
/// 食べ終わりはボタンでも押せるが、手が汚れていることも多いので
/// 「ごちそうさま」と言うだけでも終われるようにする。
public enum MealVoiceCommand {

    /// 食べ終わりとみなす言い方。
    public static let finishPhrases = [
        "ごちそうさま",
        "ごちそうさん",
        "たべおわった",
        "たべおわり",
        "おわった"
    ]

    /// 言い方の揺れを吸収して、食べ終わりの合図かどうかを判定する。
    ///
    /// 3〜6歳の発音と音声認識のぶれを考えて、濁点・長音・促音の違いは無視する。
    public static func isFinish(_ transcript: String) -> Bool {
        let key = matchKey(transcript)
        guard !key.isEmpty else { return false }
        return finishPhrases.contains { phrase in
            let phraseKey = matchKey(phrase)
            return !phraseKey.isEmpty && key.contains(phraseKey)
        }
    }

    /// 比較用のキー。
    /// 長音は「ごちそーさま」「ごちそうさま」どちらでも返ってくるので、
    /// 「ー」も「う」も落としてから比べる。
    private static func matchKey(_ text: String) -> String {
        JapaneseTextNormalizer.looseKey(text).replacingOccurrences(of: "う", with: "")
    }
}
