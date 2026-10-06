import XCTest
@testable import PiyoCore

final class MealVoiceCommandTests: XCTestCase {

    func testRecognisesTheUsualPhrase() {
        XCTAssertTrue(MealVoiceCommand.isFinish("ごちそうさま"))
        XCTAssertTrue(MealVoiceCommand.isFinish("ごちそうさまでした"))
        XCTAssertTrue(MealVoiceCommand.isFinish("ごちそうさん"))
    }

    func testRecognisesItInsideASentence() {
        XCTAssertTrue(MealVoiceCommand.isFinish("もう ごちそうさま！"))
        XCTAssertTrue(MealVoiceCommand.isFinish("ぜんぶ たべおわったよ"))
    }

    func testAbsorbsSpeechWobble() {
        // 濁点・長音のぶれは吸収する
        XCTAssertTrue(MealVoiceCommand.isFinish("こちそうさま"))
        XCTAssertTrue(MealVoiceCommand.isFinish("ごちそーさま"))
        // カタカナで返ってきても通す
        XCTAssertTrue(MealVoiceCommand.isFinish("ゴチソウサマ"))
    }

    func testIgnoresUnrelatedSpeech() {
        XCTAssertFalse(MealVoiceCommand.isFinish("もぐもぐ"))
        XCTAssertFalse(MealVoiceCommand.isFinish("おいしいね"))
        XCTAssertFalse(MealVoiceCommand.isFinish(""))
        XCTAssertFalse(MealVoiceCommand.isFinish("   "))
    }
}
