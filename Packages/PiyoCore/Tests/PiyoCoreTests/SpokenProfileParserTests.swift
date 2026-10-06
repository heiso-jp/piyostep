import XCTest
@testable import PiyoCore

final class SpokenProfileParserTests: XCTestCase {

    func testNameTakesTheNameOutOfASentence() {
        XCTAssertEqual(SpokenProfileParser.name(from: "ぼくは ゆうた です"), "ゆうた")
        XCTAssertEqual(SpokenProfileParser.name(from: "わたしのなまえは さくら"), "さくら")
        XCTAssertEqual(SpokenProfileParser.name(from: "なまえは はると だよ"), "はると")
        XCTAssertEqual(SpokenProfileParser.name(from: "みなみ といいます"), "みなみ")
    }

    func testNameKeepsAPlainName() {
        XCTAssertEqual(SpokenProfileParser.name(from: "ゆうた"), "ゆうた")
        XCTAssertEqual(SpokenProfileParser.name(from: " そら。"), "そら")
    }

    func testNameConvertsKatakanaToHiragana() {
        XCTAssertEqual(SpokenProfileParser.name(from: "ケン"), "けん")
    }

    func testNameKeepsProlongedSoundMark() {
        XCTAssertEqual(SpokenProfileParser.name(from: "りょーた"), "りょーた")
    }

    func testNameIsLimitedToEightCharacters() {
        let parsed = SpokenProfileParser.name(from: "あいうえおかきくけこ")
        XCTAssertEqual(parsed?.count, 8)
    }

    func testNameReturnsNilWhenNothingIsLeft() {
        XCTAssertNil(SpokenProfileParser.name(from: ""))
        XCTAssertNil(SpokenProfileParser.name(from: "、。"))
    }

    func testAgeAcceptsKanaAndDigits() {
        XCTAssertEqual(SpokenProfileParser.age(from: "ごさい"), 5)
        XCTAssertEqual(SpokenProfileParser.age(from: "よんさい"), 4)
        XCTAssertEqual(SpokenProfileParser.age(from: "6さい"), 6)
        XCTAssertEqual(SpokenProfileParser.age(from: "さんさい です"), 3)
    }

    func testAgeRejectsValuesOutsideTheRange() {
        XCTAssertNil(SpokenProfileParser.age(from: "じゅうさい"))
        XCTAssertNil(SpokenProfileParser.age(from: "にさい"))
        XCTAssertNil(SpokenProfileParser.age(from: "わからない"))
    }
}
