import XCTest
@testable import PiyoCore

final class MealScenePlaybackTests: XCTestCase {
    private func scene(_ id: String, count: Int = 20,
                       activities: [String] = ["eating", "resting", "cheering"]) -> MealSceneDescriptor {
        MealSceneDescriptor(id: id, encoding: "apng", files: ["\(id).apng"],
                            frameDurationsMs: Array(repeating: 100, count: count),
                            allowedActivities: activities)
    }

    private func player(_ scenes: [MealSceneDescriptor]) -> MealScenePlayback {
        MealScenePlayback(selector: MealSceneSelector(scenes: scenes, random: SeededRandomSource(seed: 123)),
                          activity: .eating)
    }

    func testEveryGestureFinishesBeforeNextAndNeverImmediatelyRepeats() {
        let p = player([scene("scene01"), scene("scene02"), scene("scene03"),
                        scene("scene04", count: 15), scene("scene05", count: 26)])
        var observed = Set<String>()
        for _ in 0 ..< 100 {
            guard let current = p.currentScene else { return XCTFail("Missing scene") }
            observed.insert(current.id)
            for index in current.frameDurationsMs.indices {
                XCTAssertEqual(p.currentScene?.id, current.id)
                XCTAssertEqual(p.frameIndex, index)
                p.advance(by: 0.1)
            }
            XCTAssertNotEqual(p.currentScene?.id, current.id)
        }
        XCTAssertEqual(observed.count, 5)
        XCTAssertEqual(p.completedSceneCount, 100)
    }

    func testActivityRequestsAreDeferredUntilSceneEnd() {
        let p = player([scene("eat", activities: ["eating"]), scene("rest", activities: ["resting"])])
        p.advance(by: 0.6)
        p.request(.resting)
        XCTAssertEqual(p.currentScene?.id, "eat")
        p.advance(by: 1.3)
        XCTAssertEqual(p.currentScene?.id, "eat")
        XCTAssertEqual(p.frameIndex, 19)
        p.advance(by: 0.1)
        XCTAssertEqual(p.currentScene?.id, "rest")
        XCTAssertEqual(p.frameIndex, 0)
    }

    func testPauseAndReducedMotionDoNotConsumeFramesOrRandomChoices() {
        let p = player([scene("a"), scene("b")])
        p.advance(by: 0.7)
        let id = p.currentScene?.id
        p.isPaused = true
        p.advance(by: 40)
        XCTAssertEqual(p.elapsed, 0.7, accuracy: 0.000001)
        p.isPaused = false
        p.reduceMotion = true
        p.advance(by: 40)
        XCTAssertEqual(p.elapsed, 0.7, accuracy: 0.000001)
        XCTAssertEqual(p.currentScene?.id, id)
        XCTAssertEqual(p.completedSceneCount, 0)
        p.reduceMotion = false
        p.advance(by: 0.1)
        XCTAssertEqual(p.frameIndex, 8)
    }

    func testFinishImmediatelyStopsAndCannotRestartByStaleActivityUpdate() {
        let p = player([scene("a"), scene("b")])
        p.advance(by: 0.8)
        p.request(.finished)
        p.advance(by: 20)
        p.request(.eating)
        p.advance(by: 20)
        XCTAssertTrue(p.isFinished)
        XCTAssertEqual(p.elapsed, 0.8, accuracy: 0.000001)
        XCTAssertEqual(p.completedSceneCount, 0)
    }

    func testEmptyPoolAndSingleEligibleSceneAreSafe() {
        let empty = player([])
        empty.advance(by: 1)
        XCTAssertNil(empty.currentScene)
        let single = player([scene("only")])
        single.advance(by: 2)
        XCTAssertEqual(single.currentScene?.id, "only")
        XCTAssertEqual(single.completedSceneCount, 1)
    }

    func testFrameTimingAndMalformedInput() {
        let variable = MealSceneDescriptor(id: "v", encoding: "pngSequence",
                                          files: ["v-0.png", "v-1.png", "v-2.png"],
                                          frameDurationsMs: [40, 120, 80])
        XCTAssertTrue(variable.isValid)
        XCTAssertEqual(variable.frameIndex(at: 0.039), 0)
        XCTAssertEqual(variable.frameIndex(at: 0.040), 1)
        XCTAssertEqual(variable.frameIndex(at: 0.159), 1)
        XCTAssertEqual(variable.frameIndex(at: 0.160), 2)
        XCTAssertFalse(MealSceneDescriptor.isSafeResourceName("../outside.png"))
        XCTAssertFalse(MealSceneDescriptor.isSafeResourceName("https://example.com/a.png"))
        XCTAssertFalse(MealSceneDescriptor(id: "bad", encoding: "apng", files: ["bad.png"],
                                           frameDurationsMs: [0]).isValid)
        let p = player([scene("ok")])
        p.advance(by: .infinity)
        p.advance(by: .nan)
        p.advance(by: -1)
        XCTAssertEqual(p.elapsed, 0)
    }

    func testCompactMediaManifestDecodesWithoutChangingTimes() throws {
        let json = #"{"schemaVersion":1,"width":640,"height":360,"frameDurationMs":100,"finishedImage":"finished.png","scenes":[{"id":"scene01","file":"01-small_flap.apng","frameCount":20,"durationMs":2000},{"id":"scene04","file":"04-eyes_closed.apng","frameCount":15,"durationMs":1500},{"id":"scene05","file":"05-large_hop.apng","frameCount":26,"durationMs":2600}],"allowedActivities":["eating","resting","cheering"]}"#
        let manifest = try JSONDecoder().decode(MealSceneManifest.self, from: Data(json.utf8))
        XCTAssertTrue(manifest.isValid)
        XCTAssertEqual(manifest.characterID, "piyo")
        XCTAssertEqual(manifest.finishedImage, "finished.png")
        XCTAssertEqual(manifest.scenes.map(\.duration), [2, 1.5, 2.6])
        XCTAssertEqual(manifest.scenes[0].files, ["01-small_flap.apng"])
        let roundTrip = try JSONDecoder().decode(MealSceneManifest.self,
                                                from: JSONEncoder().encode(manifest))
        XCTAssertEqual(roundTrip, manifest)
        let invalid = json.replacingOccurrences(of: "\"durationMs\":2600", with: "\"durationMs\":2500")
        XCTAssertThrowsError(try JSONDecoder().decode(MealSceneManifest.self, from: Data(invalid.utf8)))
    }

    func testSeedIsDeterministicAndInvalidManifestIsRejected() {
        let clips = [scene("a"), scene("b"), scene("c")]
        let a = MealSceneSelector(scenes: clips, random: SeededRandomSource(seed: 44))
        let b = MealSceneSelector(scenes: clips, random: SeededRandomSource(seed: 44))
        for _ in 0 ..< 100 { XCTAssertEqual(a.next(for: .eating)?.id, b.next(for: .eating)?.id) }
        XCTAssertNil(a.next(for: .finished))
        XCTAssertFalse(MealSceneManifest(characterID: "piyo", width: 640, height: 360,
                                          scenes: [scene("a"), scene("a")]).isValid)
    }
}
