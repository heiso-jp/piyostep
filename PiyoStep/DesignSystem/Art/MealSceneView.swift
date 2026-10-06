import SwiftUI
import UIKit
import ImageIO
import PiyoCore

/// Optional media enhancement. The real scene assets are installed separately.
/// All other buddies, missing resources and decode failures keep the existing art.
struct MealSceneView<Fallback: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let character: CharacterDefinition
    let activity: CharacterActivity
    let isPlaying: Bool
    let reduceAnimations: Bool
    let seed: UInt64
    /// true なら枠いっぱいに敷き詰める（はみ出た端は切る）。
    let fillsFrame: Bool
    let fallback: (Bool) -> Fallback
    @State private var didFail = false

    init(character: CharacterDefinition, activity: CharacterActivity, isPlaying: Bool,
         reduceAnimations: Bool, seed: UInt64, fillsFrame: Bool = false,
         @ViewBuilder fallback: @escaping (Bool) -> Fallback) {
        self.character = character
        self.activity = activity
        self.isPlaying = isPlaying
        self.reduceAnimations = reduceAnimations
        self.seed = seed
        self.fillsFrame = fillsFrame
        self.fallback = fallback
    }

    /// このキャラクター用のアニメが入っているか。
    static func hasScenes(for character: CharacterDefinition) -> Bool {
        MealSceneAssets.bundled?.manifest.characterID == character.id
    }

    /// アニメの縦横比（幅 / 高さ）。
    static var sceneAspectRatio: CGFloat? {
        guard let manifest = MealSceneAssets.bundled?.manifest else { return nil }
        return CGFloat(manifest.width) / CGFloat(manifest.height)
    }

    var body: some View {
        Group {
            if !didFail, let assets = MealSceneAssets.bundled,
               assets.manifest.characterID == character.id {
                MealSceneRepresentable(
                    assets: assets,
                    activity: activity,
                    isPlaying: isPlaying && scenePhase == .active,
                    reduceMotion: systemReduceMotion || reduceAnimations,
                    seed: seed,
                    fillsFrame: fillsFrame,
                    onFailure: { didFail = true }
                )
                .modifier(MealSceneFrame(
                    aspectRatio: CGFloat(assets.manifest.width) / CGFloat(assets.manifest.height),
                    fillsFrame: fillsFrame
                ))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(character.name)、\(activity.childCaption)")
            } else {
                fallback(isPlaying && scenePhase == .active && !systemReduceMotion &&
                         !reduceAnimations && activity != .finished)
            }
        }
    }
}

/// 合わせて置くときは絵の縦横比で枠を決める。
/// 敷き詰めるときは与えられた枠をそのまま使い、はみ出た分は UIImageView 側で切る。
private struct MealSceneFrame: ViewModifier {
    let aspectRatio: CGFloat
    let fillsFrame: Bool

    func body(content: Content) -> some View {
        if fillsFrame {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            content.aspectRatio(aspectRatio, contentMode: .fit)
        }
    }
}

private struct MealSceneAssets {
    let manifest: MealSceneManifest
    let urls: [String: URL]
    static let bundled: MealSceneAssets? = load(bundle: .main)

    private static func load(bundle: Bundle) -> MealSceneAssets? {
        // Synchronized Xcode groups may flatten resource files at copy time.
        guard let manifestURL = bundle.url(forResource: "piyo-meal-scenes", withExtension: "json", subdirectory: "MealScenes")
                ?? bundle.url(forResource: "piyo-meal-scenes", withExtension: "json", subdirectory: "Resources/MealScenes")
                ?? bundle.url(forResource: "piyo-meal-scenes", withExtension: "json"),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(MealSceneManifest.self, from: data),
              manifest.isValid else { return nil }
        var urls: [String: URL] = [:]
        for file in Set(manifest.scenes.flatMap(\.files) + [manifest.finishedImage].compactMap { $0 }) {
            let relative = manifestURL.deletingLastPathComponent().appendingPathComponent(file)
            if FileManager.default.isReadableFile(atPath: relative.path) {
                urls[file] = relative
            } else if let bundled = bundle.url(forResource: file, withExtension: nil),
                      FileManager.default.isReadableFile(atPath: bundled.path) {
                urls[file] = bundled
            } else {
                return nil
            }
        }
        return MealSceneAssets(manifest: manifest, urls: urls)
    }
}

private struct MealSceneRepresentable: UIViewRepresentable {
    let assets: MealSceneAssets
    let activity: CharacterActivity
    let isPlaying: Bool
    let reduceMotion: Bool
    let seed: UInt64
    let fillsFrame: Bool
    let onFailure: () -> Void

    func makeUIView(context: Context) -> MealSceneSurface {
        let view = MealSceneSurface(assets: assets, seed: seed, activity: activity)
        view.imageContentMode = fillsFrame ? .scaleAspectFill : .scaleAspectFit
        view.onFailure = onFailure
        view.update(activity: activity, isPlaying: isPlaying, reduceMotion: reduceMotion)
        return view
    }

    func updateUIView(_ view: MealSceneSurface, context: Context) {
        view.onFailure = onFailure
        view.update(activity: activity, isPlaying: isPlaying, reduceMotion: reduceMotion)
    }

    static func dismantleUIView(_ view: MealSceneSurface, coordinator: ()) { view.stop() }
}

@MainActor
private final class MealSceneSurface: UIView {
    private let imageView = UIImageView()
    private let assets: MealSceneAssets
    private let playback: MealScenePlayback
    private var displayLink: CADisplayLink?
    private var previousTimestamp: CFTimeInterval?
    private var presentedKey: String?
    private var sourceSceneID: String?
    private var animatedSource: CGImageSource?
    private var failed = false
    private var wantsPlayback = false
    var onFailure: (() -> Void)?
    var imageContentMode: UIView.ContentMode {
        get { imageView.contentMode }
        set { imageView.contentMode = newValue }
    }

    init(assets: MealSceneAssets, seed: UInt64, activity: CharacterActivity) {
        self.assets = assets
        // Independent stream; never draws from the race plan's RNG.
        playback = MealScenePlayback(
            selector: MealSceneSelector(scenes: assets.manifest.scenes,
                                        random: SeededRandomSource(seed: seed ^ 0x5049594F53434E45)),
            activity: activity,
            // 素材の 1 本は短いので、同じ動きを 3 回続けてから次へ移る。
            playsPerScene: 3
        )
        super.init(frame: .zero)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let proxy = MealSceneDisplayLinkTarget(owner: self)
        let link = CADisplayLink(target: proxy, selector: #selector(proxy.tick(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    required init?(coder: NSCoder) { return nil }

    func update(activity: CharacterActivity, isPlaying: Bool, reduceMotion: Bool) {
        playback.request(activity)
        playback.isPaused = !isPlaying
        playback.reduceMotion = reduceMotion
        wantsPlayback = isPlaying && !reduceMotion && !playback.isFinished && !failed
        applyPlaybackState()
        presentFrame()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyPlaybackState()
    }

    private func applyPlaybackState() {
        let paused = !wantsPlayback || window == nil
        if displayLink?.isPaused != paused {
            previousTimestamp = nil
            displayLink?.isPaused = paused
        }
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard !failed, wantsPlayback else { return }
        let now = link.timestamp
        defer { previousTimestamp = now }
        guard let previous = previousTimestamp else { return }
        // A UI stall is not permission to skip several gestures. Resume from this frame.
        let delta = max(0, min(now - previous, 0.1))
        playback.advance(by: delta)
        presentFrame()
    }

    private func presentFrame() {
        guard !failed else { return }
        if playback.isFinished || playback.reduceMotion {
            if let name = assets.manifest.finishedImage {
                guard presentedKey != "poster" else { return }
                guard let url = assets.urls[name],
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceGetCount(source) == 1,
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      image.width == assets.manifest.width, image.height == assets.manifest.height else { fail(); return }
                imageView.image = UIImage(cgImage: image)
                presentedKey = "poster"
                return
            }
        }
        guard let scene = playback.currentScene else { return }
        let index = playback.frameIndex
        let key = "\(scene.id):\(index)"
        guard key != presentedKey else { return }
        let source: CGImageSource
        let sourceIndex: Int
        if scene.encoding == "apng" {
            if sourceSceneID != scene.id {
                guard let name = scene.files.first, let url = assets.urls[name],
                      let decoded = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                      CGImageSourceGetCount(decoded) == scene.frameDurationsMs.count else { fail(); return }
                animatedSource = decoded
                sourceSceneID = scene.id
            }
            guard let decoded = animatedSource else { fail(); return }
            source = decoded
            sourceIndex = index
        } else {
            guard scene.files.indices.contains(index), let url = assets.urls[scene.files[index]],
                  let decoded = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(decoded) == 1 else { fail(); return }
            source = decoded
            sourceIndex = 0
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, sourceIndex, nil),
              image.width == assets.manifest.width, image.height == assets.manifest.height else { fail(); return }
        imageView.image = UIImage(cgImage: image)
        presentedKey = key
    }

    private func fail() {
        failed = true
        stop()
        // SwiftUI state must not be changed synchronously inside updateUIView.
        DispatchQueue.main.async { [weak self] in self?.onFailure?() }
    }

    func stop() {
        wantsPlayback = false
        playback.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        animatedSource = nil
        previousTimestamp = nil
    }

    deinit { displayLink?.invalidate() }
}

@MainActor
private final class MealSceneDisplayLinkTarget: NSObject {
    weak var owner: MealSceneSurface?
    init(owner: MealSceneSurface) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}
