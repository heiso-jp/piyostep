import SwiftUI
import PiyoCore

/// ご飯タイマーの入れ物。準備 → 競争 → 結果 を 1 画面で切り替える。
struct MealRaceContainerView: View {
    @Environment(\.piyoLayout) private var layout
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var model: MealRaceViewModel?

    var body: some View {
        ZStack {
            PiyoBackground(tint: PiyoTheme.success)
            if let model {
                switch model.stage {
                case .ready:
                    MealSetupView(model: model, onClose: { dismiss() })
                case .countdown(let value):
                    CountdownView(value: value, character: model.character)
                case .racing:
                    MealRaceView(model: model, onClose: { dismiss() })
                case .finished:
                    MealResultView(model: model, onDone: { dismiss() })
                }
            }
        }
        .onAppear {
            if model == nil {
                model = MealRaceViewModel(environment: environment)
            }
        }
        .onDisappear {
            model?.cancel()
        }
    }
}

/// ごはんタイマーの場面（部屋の中のキャラクター）を画面いっぱいに敷く。
/// アニメが無いキャラクターは、これまでの絵を真ん中に置く。
struct MealStageBackdrop: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.piyoLayout) private var layout

    let character: CharacterDefinition
    var activity: CharacterActivity = .resting
    var isPlaying: Bool = false
    var seed: UInt64 = 0
    var fallbackMood: CharacterMood = .happy

    var body: some View {
        GeometryReader { proxy in
            MealSceneView(
                character: character,
                activity: activity,
                isPlaying: isPlaying,
                // 止めておくときは、静止画を出す。
                reduceAnimations: !isPlaying || environment.launchArguments.reduceAnimations,
                seed: seed,
                fillsFrame: true
            ) { animate in
                CharacterArtView(
                    character: character,
                    mood: fallbackMood,
                    size: min(proxy.size.height * 0.5, CGFloat(layout.artSized(220))),
                    isAnimated: animate
                )
                .id(animate)
                .position(MealStageGeometry.point(x: 0.5, y: 0.55, in: proxy.size))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

/// 場面の絵の上の位置を、画面上の位置に直す。
/// 絵は縦横比を保ったまま画面いっぱいに敷く（はみ出た端は切る）ので、その計算に合わせる。
enum MealStageGeometry {
    static var aspectRatio: CGFloat {
        MealSceneView<EmptyView>.sceneAspectRatio ?? 16.0 / 9.0
    }

    /// 絵の幅が画面上で何 pt になるか。
    static func sceneWidth(in size: CGSize) -> CGFloat {
        max(size.width, size.height * aspectRatio)
    }

    /// x, y は絵の中の割合（0〜1）。
    static func point(x: CGFloat, y: CGFloat, in size: CGSize) -> CGPoint {
        let width = sceneWidth(in: size)
        let height = width / aspectRatio
        return CGPoint(
            x: (size.width - width) / 2 + width * x,
            y: (size.height - height) / 2 + height * y
        )
    }
}

/// スタート前。場面を見せながら、保護者の設定内容を出してから始める。
struct MealSetupView: View {
    @Environment(\.piyoLayout) private var layout
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: MealRaceViewModel
    var onClose: () -> Void

    var body: some View {
        ZStack {
            MealStageBackdrop(character: model.character)

            VStack {
                HStack {
                    BackCircleButton(action: onClose)
                    Spacer()
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    startPanel
                        .frame(maxWidth: CGFloat(layout.sized(360)))
                }
            }
            .padding(CGFloat(layout.sized(20)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.mealSetup)
        .onAppear {
            environment.speak(model.character.raceIntroLine)
        }
    }

    private func minuteButton(_ minutes: Int) -> some View {
        let isSelected = model.targetMinutes == minutes
        return Button {
            model.select(minutes: minutes)
        } label: {
            VStack(spacing: 0) {
                Text("\(minutes)")
                    .piyoFont(size: 22, weight: .heavy)
                Text("ふん")
                    .piyoFont(size: 11, weight: .semibold)
            }
            .foregroundStyle(isSelected ? .white : PiyoTheme.textSoft)
            .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(56)))
            .background(
                RoundedRectangle(cornerRadius: PiyoTheme.smallCornerRadius, style: .continuous)
                    .fill(isSelected ? PiyoTheme.success : PiyoTheme.surfaceSunken)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(A11yID.mealMinutes)\(minutes)")
        .accessibilityLabel("\(minutes)ふん")
    }

    private var startPanel: some View {
        VStack(spacing: CGFloat(layout.sized(12))) {
            Text(model.character.raceIntroLine)
                .piyoFont(.body)
                .foregroundStyle(PiyoTheme.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(3)

            // 食べる時間はその日の量で変わるので、始める前にここで選べるようにする。
            Text("なんぷんで たべる？")
                .piyoFont(.caption)
                .foregroundStyle(PiyoTheme.textSoft)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(MealRaceViewModel.selectableMinutes, id: \.self) { minutes in
                    minuteButton(minutes)
                }
            }

            BigButton(color: PiyoTheme.success, minHeight: CGFloat(layout.sized(84)), action: { model.begin() }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .bold))
                    Text("スタート！")
                        .piyoFont(.title)
                }
            }
            .accessibilityIdentifier(A11yID.mealStart)
        }
        .padding(CGFloat(layout.sized(16)))
        .background(
            RoundedRectangle(cornerRadius: PiyoTheme.cornerRadius, style: .continuous)
                .fill(PiyoTheme.surface.opacity(0.92))
        )
    }
}

/// 3・2・1 のカウントダウン。
struct CountdownView: View {
    @Environment(\.piyoLayout) private var layout

    let value: Int
    let character: CharacterDefinition

    var body: some View {
        ZStack {
            MealStageBackdrop(character: character, fallbackMood: .cheering)

            Text("\(value)")
                .piyoFont(size: 140, weight: .heavy)
                .foregroundStyle(PiyoTheme.primaryDeep)
                .shadow(color: .white.opacity(0.9), radius: 12)
                .transition(.scale.combined(with: .opacity))
                .id(value)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
    }
}

/// 競争中。アニメを画面いっぱいに出し、ごはんだけを置く。
/// ごはんはキャラクターの進み具合に合わせて減っていく。
struct MealRaceView: View {
    @Environment(\.piyoLayout) private var layout
    @Bindable var model: MealRaceViewModel
    var onClose: () -> Void

    var body: some View {
        ZStack {
            MealStageBackdrop(
                character: model.character,
                activity: model.snapshot.characterActivity,
                isPlaying: model.stage == .racing,
                seed: model.engine.configuration.seed,
                fallbackMood: model.characterMood
            )

            // ごはん（茶碗）。キャラクターの左手前、敷物の上に置く（右下は「たべおわった！」が来る）。
            // 絵の下端は画面の外に切れることがあるので、お皿が収まる高さまで持ち上げる。
            GeometryReader { proxy in
                let plateWidth = min(MealStageGeometry.sceneWidth(in: proxy.size) * 0.17,
                                     proxy.size.height * 0.4)
                let anchor = MealStageGeometry.point(x: 0.33, y: 0.84, in: proxy.size)
                RiceBowlView(
                    fullness: model.characterPlateFullness,
                    size: plateWidth,
                    foodName: model.character.favoriteFood
                )
                .position(x: anchor.x, y: min(anchor.y, proxy.size.height - plateWidth * 0.39 - 16))
            }
            .ignoresSafeArea()

            VStack {
                header
                Spacer(minLength: 0)
                HStack {
                    Spacer(minLength: 0)
                    finishButton
                }
            }
            .padding(CGFloat(layout.sized(16)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.mealRace)
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(PiyoTheme.textSoft)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(PiyoTheme.surface.opacity(0.9)))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .foregroundStyle(PiyoTheme.textSoft)
                Text(model.remainingText)
                    .piyoFont(.headline)
                    .foregroundStyle(PiyoTheme.text)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(PiyoTheme.surface.opacity(0.9)))

            Spacer()
            Color.clear.frame(width: 52, height: 52)
        }
    }

    private var finishButton: some View {
        BigButton(color: PiyoTheme.success, minHeight: CGFloat(layout.sized(80)), action: { model.finish() }) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30, weight: .bold))
                Text("たべおわった！")
                    .piyoFont(.headline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: CGFloat(layout.sized(280)))
        .accessibilityIdentifier(A11yID.mealFinish)
    }
}

/// 結果。どちらが先でも、必ず前向きな表現にする。
struct MealResultView: View {
    @Environment(\.piyoLayout) private var layout
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: MealRaceViewModel
    var onDone: () -> Void

    var body: some View {
        AdaptiveColumn(spacing: 24, maxWidth: 560) {
            Spacer(minLength: 0)

            if MealSceneView<EmptyView>.hasScenes(for: model.character) {
                MealSceneView(character: model.character, activity: .finished, isPlaying: false,
                              reduceAnimations: true, seed: 0) { _ in EmptyView() }
                    .frame(height: CGFloat(layout.artSized(150)))
                    .clipShape(RoundedRectangle(cornerRadius: PiyoTheme.cornerRadius, style: .continuous))
            } else {
                HStack(spacing: -16) {
                    CharacterArtView(character: model.character, mood: .cheering, size: CGFloat(layout.artSized(140)))
                    CharacterArtView(character: environment.buddyCharacter, mood: .happy, size: CGFloat(layout.artSized(120)))
                }
            }

            if let result = model.result {
                Text(result.headline)
                    .piyoFont(size: 44, weight: .heavy)
                    .foregroundStyle(PiyoTheme.primaryDeep)

                Text(result.subline)
                    .piyoFont(.headline)
                    .foregroundStyle(PiyoTheme.text)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 12)

                StarRewardView(stars: result.starsEarned, maximum: 3, size: 40)

                if !result.childFinishedFirst {
                    Text(model.character.watchingLine)
                        .piyoFont(.body)
                        .foregroundStyle(PiyoTheme.textSoft)
                }
            }

            Spacer(minLength: 0)

            BigButton(color: PiyoTheme.success, action: onDone) {
                HStack(spacing: 10) {
                    Image(systemName: "house.fill")
                    Text("ホームへ")
                        .piyoFont(.headline)
                }
            }
            .accessibilityIdentifier(A11yID.mealResultDone)
        }
        .padding(CGFloat(layout.sized(20)))
        .piyoContentWidth(layout)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.mealResult)
        .overlay {
            ConfettiView(isActive: true)
        }
    }
}
