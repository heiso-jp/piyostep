import XCTest
@testable import PiyoCore

/// 書きの評価が「形」を見ているかどうかの確認。
final class TraceShapeTests: XCTestCase {

    /// 左半分だけが文字になっている 20x20 のお手本。
    private let mask = GlyphMask.rectangle(width: 20, height: 20, rect: (x: 2, y: 4, w: 6, h: 12))

    /// お手本の上だけを 1 画でなぞる。
    private var neatStroke: [[TracePoint]] {
        [(4 ... 15).map { TracePoint(x: 0.25, y: Double($0) / 20.0) }]
    }

    /// 画面いっぱいをぐりぐり塗りつぶす。
    private var scribble: [[TracePoint]] {
        (2 ... 18).map { row in
            (0 ... 19).map { column in
                TracePoint(x: Double(column) / 20.0, y: Double(row) / 20.0)
            }
        }
    }

    func testNeatTracingScoresWell() {
        let evaluation = TraceEvaluator.evaluate(mask: mask, strokes: neatStroke, brushRadius: 0.08)
        XCTAssertGreaterThan(evaluation.score, 0.55, "お手本どおりなぞれば通る")
    }

    func testScribblingDoesNotPass() {
        let evaluation = TraceEvaluator.evaluate(mask: mask, strokes: scribble, brushRadius: 0.08)
        XCTAssertGreaterThan(evaluation.coverage, 0.9, "塗りつぶしなので覆えてはいる")
        XCTAssertLessThan(evaluation.precision, 0.5, "はみ出しだらけ")
        XCTAssertLessThan(evaluation.score, 0.55, "塗りつぶしでは通さない")
    }

    func testStrokeCountIsForgivingByOne() {
        XCTAssertEqual(TraceEvaluator.strokeMatch(drawn: 3, expected: 3), 1.0)
        XCTAssertEqual(TraceEvaluator.strokeMatch(drawn: 2, expected: 3), 1.0, "続け書きは許す")
        XCTAssertLessThan(TraceEvaluator.strokeMatch(drawn: 6, expected: 3), 1.0)
        XCTAssertEqual(TraceEvaluator.strokeMatch(drawn: 3, expected: nil), 1.0, "画数不明なら下げない")
    }

    func testWrongStrokeCountLowersTheScore() {
        let matching = TraceEvaluator.evaluate(
            mask: mask, strokes: neatStroke, brushRadius: 0.08, expectedStrokeCount: 1
        )
        let mismatched = TraceEvaluator.evaluate(
            mask: mask, strokes: neatStroke, brushRadius: 0.08, expectedStrokeCount: 6
        )
        XCTAssertGreaterThan(matching.score, mismatched.score)
    }

    func testStrokeCountsCoverEveryKana() {
        for card in KanaCatalog.all {
            XCTAssertNotNil(StrokeCounts.count(for: card.hiragana), "\(card.hiragana) の画数がない")
            XCTAssertNotNil(StrokeCounts.count(for: card.katakana), "\(card.katakana) の画数がない")
        }
    }

    func testStrokeCountsCoverEveryLetter() {
        for card in AlphabetCatalog.all {
            XCTAssertNotNil(StrokeCounts.count(for: card.uppercase), "\(card.uppercase) の画数がない")
        }
    }
}
