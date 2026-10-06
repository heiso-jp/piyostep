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

/// スタート前。保護者の設定内容を見せてから始める。
struct MealSetupView: View {
    @Environment(\.piyoLayout) private var layout
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: MealRaceViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                BackCircleButton(action: onClose)
                Spacer()
            }

            Spacer(minLength: 0)

            CharacterArtView(character: model.character, mood: .happy, size: CGFloat(layout.artSized(170)))

            Text(model.character.raceIntroLine)
                .piyoFont(.headline)
                .foregroundStyle(PiyoTheme.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)

            PiyoCard {
                HStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 28))
                            .foregroundStyle(PiyoTheme.success)
                        Text("\(model.targetMinutes)ふん")
                            .piyoFont(.headline)
                            .foregroundStyle(PiyoTheme.text)
                    }
                    Divider().frame(height: 48)
                    VStack(spacing: 6) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 28))
                            .foregroundStyle(PiyoTheme.success)
                        Text(model.character.favoriteFood)
                            .piyoFont(.body)
                            .foregroundStyle(PiyoTheme.text)
                    }
                }
            }

            Spacer(minLength: 0)

            BigButton(color: PiyoTheme.success, minHeight: CGFloat(layout.sized(116)), action: { model.begin() }) {
                HStack(spacing: 12) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 34, weight: .bold))
                    Text("スタート！")
                        .piyoFont(.title)
                }
            }
            .accessibilityIdentifier(A11yID.mealStart)
        }
        .padding(CGFloat(layout.sized(20)))
        .piyoContentWidth(layout)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.mealSetup)
        .onAppear {
            environment.speak(model.character.raceIntroLine)
        }
    }
}

/// 3・2・1 のカウントダウン。
struct CountdownView: View {
    @Environment(\.piyoLayout) private var layout

    let value: Int
    let character: CharacterDefinition

    var body: some View {
        VStack(spacing: 28) {
            CharacterArtView(character: character, mood: .cheering, size: CGFloat(layout.artSized(160)))
            Text("\(value)")
                .piyoFont(size: 140, weight: .heavy)
                .foregroundStyle(PiyoTheme.primaryDeep)
                .transition(.scale.combined(with: .opacity))
                .id(value)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
    }
}

/// 競争中。
struct MealRaceView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.piyoLayout) private var layout
    @Bindable var model: MealRaceViewModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            header

            RaceTrackView(
                childProgress: model.snapshot.childProgress,
                characterProgress: model.snapshot.characterProgress,
                character: model.character,
                childName: model.childName
            )
            .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 12) {
                plateColumn(
                    title: model.childName,
                    fullness: model.childPlateFullness,
                    isChild: true
                )
                plateColumn(
                    title: model.character.name,
                    fullness: model.characterPlateFullness,
                    isChild: false
                )
            }

            messageBubble

            Spacer(minLength: 0)

            BigButton(color: PiyoTheme.success, minHeight: CGFloat(layout.sized(132)), action: { model.finish() }) {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 42, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("たべおわった！")
                            .piyoFont(.title)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("おさらが からっぽに なったら おしてね")
                            .piyoFont(size: 13, weight: .semibold)
                            .opacity(0.9)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.vertical, 12)
            }
            .accessibilityIdentifier(A11yID.mealFinish)
        }
        .padding(20)
        .piyoContentWidth(layout)
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

            Spacer()
            Color.clear.frame(width: 52, height: 52)
        }
    }

    private func plateColumn(title: String, fullness: Double, isChild: Bool) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .piyoFont(.body)
                .foregroundStyle(PiyoTheme.textSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if isChild {
                Button {
                    model.takeBite()
                } label: {
                    VStack(spacing: 6) {
                        PlateView(fullness: fullness, size: CGFloat(layout.artSized(140)), foodName: "ごはん")
                        Text("もぐもぐ！")
                            .piyoFont(.caption)
                            .foregroundStyle(PiyoTheme.primaryDeep)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11yID.mealBite)
            } else {
                MealSceneView(
                    character: model.character,
                    activity: model.snapshot.characterActivity,
                    isPlaying: model.stage == .racing,
                    reduceAnimations: environment.launchArguments.reduceAnimations,
                    seed: model.engine.configuration.seed
                ) { animate in
                    VStack(spacing: 6) {
                        CharacterArtView(character: model.character, mood: model.characterMood,
                                         size: CGFloat(layout.artSized(86)), isAnimated: animate)
                            .id(animate)
                        PlateView(
                            fullness: fullness,
                            size: CGFloat(layout.artSized(120)),
                            foodName: model.character.favoriteFood
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var messageBubble: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .foregroundStyle(PiyoTheme.cheer)
            Text(model.characterMessage)
                .piyoFont(.body)
                .foregroundStyle(PiyoTheme.text)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: PiyoTheme.smallCornerRadius)
                .fill(PiyoTheme.surface)
        )
    }
}

/// 結果。どちらが先でも、必ず前向きな表現にする。
struct MealResultView: View {
    @Environment(\.piyoLayout) private var layout
    @Environment(AppEnvironment.self) private var environment
    @Bindable var model: MealRaceViewModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            HStack(spacing: -16) {
                CharacterArtView(character: model.character, mood: .cheering, size: CGFloat(layout.artSized(140)))
                CharacterArtView(character: environment.buddyCharacter, mood: .happy, size: CGFloat(layout.artSized(120)))
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
