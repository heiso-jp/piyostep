import Foundation
import SwiftData
import PiyoCore

/// UI テスト用に、決まった文字列を何度でも返す音声認識。
final class ScriptedSpeechRecognizer: SpeechRecognizing {
    private let transcripts: [String]
    private var index = 0

    var authorizationStatus: SpeechAuthorizationStatus = .authorized
    var audioLevel: Double = 0.6

    init(transcripts: [String]) {
        self.transcripts = transcripts
    }

    func isAvailable(for locale: RecognitionLocale) -> Bool { true }

    func requestAuthorization(completion: @escaping (SpeechAuthorizationStatus) -> Void) {
        completion(.authorized)
    }

    func startListening(
        locale: RecognitionLocale,
        mode: SpeechListeningMode,
        onResult: @escaping (SpeechRecognitionResult) -> Void,
        onFailure: @escaping (SpeechRecognitionFailure) -> Void
    ) {
        guard !transcripts.isEmpty else {
            onFailure(.noSpeechDetected)
            return
        }
        let transcript = transcripts[index % transcripts.count]
        index += 1
        // 実機と同じように少し遅れて結果が返るようにする。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onResult(SpeechRecognitionResult(transcript: transcript, confidence: 0.9, isFinal: true))
        }
    }

    func stopListening() {}
}

enum AppEnvironmentFactory {

    /// 実機・シミュレータで動かす本番構成。
    @MainActor
    static func makeLive(launchArguments: LaunchArguments = LaunchArguments.parse()) -> AppEnvironment {
        let keyValueStore: KeyValueStoring
        if launchArguments.useInMemoryStore {
            keyValueStore = InMemoryKeyValueStore()
        } else {
            keyValueStore = UserDefaultsKeyValueStore()
        }

        let historyStore: LearningHistoryStoring
        do {
            let container = try PiyoSchema.makeContainer(inMemory: launchArguments.useInMemoryStore)
            historyStore = SwiftDataLearningHistoryStore(context: ModelContext(container))
        } catch {
            // 永続化に失敗しても遊べるようにする。
            historyStore = InMemoryLearningHistoryStore()
        }

        let recognizer: SpeechRecognizing
        if !launchArguments.voiceScript.isEmpty {
            recognizer = ScriptedSpeechRecognizer(transcripts: launchArguments.voiceScript)
        } else if launchArguments.isUITest {
            recognizer = ScriptedSpeechRecognizer(transcripts: [])
        } else {
            recognizer = SystemSpeechRecognizer()
        }

        return AppEnvironment(
            settingsStore: CodableSettingsStore(store: keyValueStore),
            historyStore: historyStore,
            speechRecognizer: recognizer,
            speechSynthesizer: launchArguments.isUITest ? MockSpeechSynthesizer() : SystemSpeechSynthesizer(),
            soundPlayer: launchArguments.isUITest ? MockSoundPlayer() : SystemSoundPlayer(),
            haptics: launchArguments.isUITest ? NoopHapticsService() : SystemHapticsService(),
            purchaseService: launchArguments.isUITest ? MockPurchaseService() : StoreKitPurchaseService(),
            adPresenter: ParentAreaAdPresenter(isDisabled: launchArguments.disableAds),
            // UI テストでは端末にファイルを残さない。
            profileImageStore: launchArguments.isUITest
                ? InMemoryProfileImageStore()
                : FileProfileImageStore(),
            random: launchArguments.randomSeed.map { SeededRandomSource(seed: $0) } ?? SystemRandomSource(),
            clock: SystemClock(),
            launchArguments: launchArguments
        )
    }

    /// プレビュー・テスト用のインメモリ構成。
    @MainActor
    static func makePreview(
        profile: ChildProfile? = ChildProfile(nickname: "さくら", age: 5),
        settings: AppSettings = .default,
        voiceScript: [String] = [],
        seed: UInt64 = 20_240_401,
        launchArguments: LaunchArguments = .none
    ) -> AppEnvironment {
        let keyValueStore = InMemoryKeyValueStore()
        let settingsStore = CodableSettingsStore(store: keyValueStore)
        settingsStore.save(settings)
        settingsStore.saveProfile(profile)

        let environment = AppEnvironment(
            settingsStore: settingsStore,
            historyStore: InMemoryLearningHistoryStore(),
            speechRecognizer: ScriptedSpeechRecognizer(transcripts: voiceScript),
            speechSynthesizer: MockSpeechSynthesizer(),
            soundPlayer: MockSoundPlayer(),
            haptics: NoopHapticsService(),
            purchaseService: MockPurchaseService(),
            adPresenter: MockAdPresenter(allow: false),
            random: SeededRandomSource(seed: seed),
            clock: SystemClock(),
            launchArguments: launchArguments
        )
        environment.bootstrap()
        return environment
    }
}
