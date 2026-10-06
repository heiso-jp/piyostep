import Foundation

/// A scene is one complete gesture, never an arbitrary random frame.
public struct MealSceneDescriptor: Codable, Equatable, Sendable {
    public let id: String
    /// `apng`: one animated .png/.apng file. `pngSequence`: one file per displayed frame.
    public let encoding: String
    public let files: [String]
    public let frameDurationsMs: [Int]
    public let allowedActivities: [String]

    public init(id: String, encoding: String, files: [String], frameDurationsMs: [Int],
                allowedActivities: [String] = ["eating", "resting", "cheering"]) {
        self.id = id
        self.encoding = encoding
        self.files = files
        self.frameDurationsMs = frameDurationsMs
        self.allowedActivities = allowedActivities
    }

    public var duration: TimeInterval {
        frameDurationsMs.reduce(0.0) { $0 + Double($1) } / 1_000
    }

    public var isValid: Bool {
        guard !id.isEmpty, !frameDurationsMs.isEmpty,
              frameDurationsMs.allSatisfy({ $0 > 0 && $0 <= 60_000 }),
              !allowedActivities.isEmpty,
              allowedActivities.allSatisfy({ CharacterActivity(rawValue: $0) != nil }),
              files.allSatisfy(Self.isSafeResourceName) else { return false }
        switch encoding {
        case "apng": return files.count == 1
        case "pngSequence": return files.count == frameDurationsMs.count
        default: return false
        }
    }

    // Relative files beneath the supplied asset directory only. No URLs or traversal.
    public static func isSafeResourceName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"),
              !name.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return false }
        return ["png", "apng"].contains((name as NSString).pathExtension.lowercased())
    }

    public func frameIndex(at seconds: TimeInterval) -> Int {
        var remaining = max(0, seconds)
        for (index, ms) in frameDurationsMs.enumerated() {
            remaining -= Double(ms) / 1_000
            if remaining < -0.000_000_001 { return index }
        }
        return max(0, frameDurationsMs.count - 1)
    }
}

public struct MealSceneManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let characterID: String
    public let width: Int
    public let height: Int
    public let scenes: [MealSceneDescriptor]
    public let finishedImage: String?

    public init(schemaVersion: Int = 1, characterID: String, width: Int, height: Int,
                scenes: [MealSceneDescriptor], finishedImage: String? = nil) {
        self.schemaVersion = schemaVersion
        self.characterID = characterID
        self.width = width
        self.height = height
        self.scenes = scenes
        self.finishedImage = finishedImage
    }

    // Accept the media team's compact manifest directly, or an explicit PNG-sequence manifest.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, characterID, width, height, scenes, finishedImage
        case frameDurationMs, allowedActivities
    }

    private struct MediaScene: Decodable {
        let id: String
        let file: String?
        let frameCount: Int?
        let durationMs: Int?
        let encoding: String?
        let files: [String]?
        let frameDurationsMs: [Int]?
        let allowedActivities: [String]?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        // This adapter is only loaded from piyo-meal-scenes.json, for the supplied piyo media.
        characterID = try c.decodeIfPresent(String.self, forKey: .characterID) ?? "piyo"
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        finishedImage = try c.decodeIfPresent(String.self, forKey: .finishedImage)
        let frameDuration = try c.decodeIfPresent(Int.self, forKey: .frameDurationMs)
        let activities = try c.decodeIfPresent([String].self, forKey: .allowedActivities) ?? []
        let media = try c.decode([MediaScene].self, forKey: .scenes)
        scenes = try media.map { item in
            let times: [Int]
            if let explicit = item.frameDurationsMs {
                times = explicit
            } else if let count = item.frameCount, count > 0, count <= 10_000,
                      let ms = frameDuration, ms > 0, ms <= 60_000 {
                times = Array(repeating: ms, count: count)
            } else {
                throw DecodingError.dataCorruptedError(forKey: .scenes, in: c,
                                                       debugDescription: "Missing or invalid frame timing")
            }
            guard !times.isEmpty, times.count <= 10_000,
                  times.allSatisfy({ $0 > 0 && $0 <= 60_000 }),
                  item.frameCount == nil || item.frameCount == times.count else {
                throw DecodingError.dataCorruptedError(forKey: .scenes, in: c,
                                                       debugDescription: "Invalid frame durations or count")
            }
            if let declared = item.durationMs,
               Int64(declared) != times.reduce(Int64(0), { $0 + Int64($1) }) {
                throw DecodingError.dataCorruptedError(forKey: .scenes, in: c,
                                                       debugDescription: "Scene duration does not match frame timing")
            }
            return MealSceneDescriptor(id: item.id, encoding: item.encoding ?? "apng",
                                       files: item.files ?? item.file.map { [$0] } ?? [],
                                       frameDurationsMs: times,
                                       allowedActivities: item.allowedActivities ?? activities)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(characterID, forKey: .characterID)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(scenes, forKey: .scenes)
        try c.encodeIfPresent(finishedImage, forKey: .finishedImage)
    }

    public var isValid: Bool {
        (finishedImage.map(MealSceneDescriptor.isSafeResourceName) ?? true) &&
        schemaVersion == 1 && !characterID.isEmpty && width > 0 && height > 0 &&
        width <= 4_096 && height <= 4_096 && !scenes.isEmpty &&
        scenes.allSatisfy(\.isValid) && Set(scenes.map(\.id)).count == scenes.count
    }
}

/// Independent of the race engine's RNG, pace, progress, rewards and selected buddy.
public final class MealSceneSelector {
    private let scenes: [MealSceneDescriptor]
    private let random: RandomSource
    public private(set) var previousID: String?

    public init(scenes: [MealSceneDescriptor], random: RandomSource) {
        self.scenes = scenes.filter(\.isValid)
        self.random = random
    }

    public func next(for activity: CharacterActivity) -> MealSceneDescriptor? {
        guard activity != .finished else { return nil }
        let pool = scenes.filter { $0.allowedActivities.contains(activity.rawValue) }
        let alternatives = pool.filter { $0.id != previousID }
        guard let selected = random.pick(alternatives.isEmpty ? pool : alternatives) else { return nil }
        previousID = selected.id
        return selected
    }
}

/// Continuous scene clock. Ordinary activity requests take effect only at clip boundaries.
/// Finished is terminal: freeze immediately and never select further eating gestures.
public final class MealScenePlayback {
    private let selector: MealSceneSelector
    public private(set) var requestedActivity: CharacterActivity
    public private(set) var currentScene: MealSceneDescriptor?
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var isFinished = false
    public private(set) var completedSceneCount = 0
    public var isPaused = false
    public var reduceMotion = false
    public var frameIndex: Int { currentScene?.frameIndex(at: elapsed) ?? 0 }

    public init(selector: MealSceneSelector, activity: CharacterActivity) {
        self.selector = selector
        requestedActivity = activity
        isFinished = activity == .finished
        currentScene = selector.next(for: activity)
    }

    public func request(_ activity: CharacterActivity) {
        guard !isFinished else { return }
        requestedActivity = activity
        if activity == .finished { isFinished = true }
        // An empty pool can become playable on a later activity without resetting a live scene.
        if currentScene == nil && !isFinished { currentScene = selector.next(for: activity) }
    }

    public func advance(by delta: TimeInterval) {
        guard !isPaused, !reduceMotion, !isFinished, delta.isFinite, delta > 0, delta <= 60,
              currentScene != nil else { return }
        elapsed += delta
        while let scene = currentScene, elapsed + 0.000_000_001 >= scene.duration {
            elapsed = max(0, elapsed - scene.duration)
            completedSceneCount += 1
            currentScene = selector.next(for: requestedActivity)
            if currentScene == nil { elapsed = 0 }
        }
    }
}
