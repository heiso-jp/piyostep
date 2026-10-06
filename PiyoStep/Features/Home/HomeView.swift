import SwiftUI
import PiyoCore

/// 学習セッションを開くための要求。
struct SessionRequest: Identifiable {
    let id = UUID()
    let kind: SessionKind
    let subject: Subject?
    let questions: [Question]
}

/// 全画面で出すもの（学習・ごはんタイマー）。
enum FullScreenRoute: Identifiable {
    case session(SessionRequest)
    case meal

    var id: String {
        switch self {
        case .session(let request): return "session-\(request.id)"
        case .meal: return "meal"
        }
    }
}

/// シートで出すもの。
enum SheetRoute: Identifiable {
    case subjectMenu(Subject)
    case collection
    case parentGate
    case parentArea

    var id: String {
        switch self {
        case .subjectMenu(let subject): return "subject-\(subject.rawValue)"
        case .collection: return "collection"
        case .parentGate: return "parentGate"
        case .parentArea: return "parentArea"
        }
    }
}

struct HomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.piyoLayout) private var layout

    @State private var fullScreenRoute: FullScreenRoute?
    @State private var sheetRoute: SheetRoute?
    @State private var unlockQueue: [UnlockableItem] = []
    /// 広告を閉じたら保護者画面を開く、という待ち状態
    @State private var opensParentAreaAfterAd = false

    var body: some View {
        ZStack {
            PiyoBackground(tint: PiyoTheme.primary)

            ScrollView {
                layoutBody
                    .padding(CGFloat(layout.spacing))
                    .piyoContentWidth(layout)
            }

            if let item = unlockQueue.first {
                Color.black.opacity(0.35).ignoresSafeArea()
                UnlockBanner(item: item) {
                    unlockQueue.removeFirst()
                    environment.haptics.tap()
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.home)
        .fullScreenCover(item: $fullScreenRoute) { route in
            // 出した先は大きさが違う（シートは一回り小さい）ので、そこで測り直す。
            PiyoLayoutReader {
                fullScreenDestination(route)
                    .environment(environment)
            }
        }
        .sheet(item: $sheetRoute) { route in
            PiyoLayoutReader {
                sheetDestination(route)
                    .environment(environment)
            }
        }
        .onAppear {
            environment.refreshProgress()
            showNextUnlockIfNeeded()
            greet()
        }
        .onChange(of: environment.pendingUnlocks.count) { _, _ in
            showNextUnlockIfNeeded()
        }
        .onChange(of: environment.isShowingParentAd) { _, isShowing in
            guard !isShowing, opensParentAreaAfterAd else { return }
            opensParentAreaAfterAd = false
            presentAfterDismiss { sheetRoute = .parentArea }
        }
    }

    // MARK: - 遷移先

    @ViewBuilder
    private func fullScreenDestination(_ route: FullScreenRoute) -> some View {
        switch route {
        case .session(let request):
            SessionView(request: request)
        case .meal:
            MealRaceContainerView()
        }
    }

    @ViewBuilder
    private func sheetDestination(_ route: SheetRoute) -> some View {
        switch route {
        case .subjectMenu(let subject):
            SubjectMenuView(subject: subject) { skill in
                // シートを閉じ切ってからフルスクリーンを出す。
                // 同じタイミングで閉じる/開くを行うと SwiftUI が取りこぼすことがある。
                sheetRoute = nil
                presentAfterDismiss { startFreePlay(skill: skill) }
            }
        case .collection:
            CollectionView()
        case .parentGate:
            ParentGateView(
                onPass: {
                    sheetRoute = nil
                    presentAfterDismiss { openParentArea() }
                },
                onCancel: { sheetRoute = nil }
            )
        case .parentArea:
            ParentAreaView()
        }
    }

    // MARK: - 並べ方

    /// いまはごはんタイマーを主役にする。学習メニューは右側に小さくまとめる。
    /// 横向きは左右に分ける。縦に積むと、高さ 390pt の iPhone 横持ちで下が画面の外に出てしまう。
    @ViewBuilder
    private var layoutBody: some View {
        if layout.shape.isLandscape {
            HStack(alignment: .top, spacing: CGFloat(layout.spacing)) {
                VStack(spacing: CGFloat(layout.spacing)) {
                    header
                    mealTimerHero
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)

                otherMenus
                    .frame(width: CGFloat(layout.sized(330)))
            }
        } else {
            VStack(spacing: CGFloat(layout.spacing)) {
                header
                mealTimerHero
                otherMenus
            }
        }
    }

    // MARK: - パーツ

    private var header: some View {
        headerContent
            .padding(CGFloat(layout.sized(16)))
            .background(
                RoundedRectangle(cornerRadius: PiyoTheme.cornerRadius, style: .continuous)
                    .fill(PiyoTheme.surface.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: PiyoTheme.cornerRadius, style: .continuous)
                    .stroke(PiyoTheme.outline.opacity(0.35), lineWidth: 1)
            )
    }

    private var headerContent: some View {
        HStack(alignment: .center, spacing: 12) {
            // 写真を選んでいればその写真、そうでなければ相棒キャラの絵。
            if environment.avatar.photoFileName != nil {
                AvatarView(
                    avatar: environment.avatar,
                    photoData: environment.avatarImageData(),
                    size: CGFloat(layout.sized(84))
                )
            } else {
                CharacterArtView(
                    character: environment.buddyCharacter,
                    mood: .happy,
                    size: CGFloat(layout.sized(84))
                )
                    .accessibilityIdentifier(A11yID.avatar)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(environment.appDisplayName)
                    .piyoFont(size: 13, weight: .semibold)
                    .foregroundStyle(PiyoTheme.primaryDeep)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(PiyoTheme.primary.opacity(0.14)))
                    .accessibilityIdentifier(A11yID.homeAppName)

                Text("\(environment.profile?.callName ?? "きみ")、こんにちは！")
                    .piyoFont(.headline)
                    .foregroundStyle(PiyoTheme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                    .accessibilityIdentifier(A11yID.homeGreeting)

                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: CGFloat(layout.fontSize(15)), weight: .bold))
                            .foregroundStyle(PiyoTheme.cheer)
                        Text("\(environment.progress.totalStars)")
                            .piyoFont(size: 17, weight: .heavy)
                            .foregroundStyle(PiyoTheme.text)
                            .accessibilityIdentifier(A11yID.homeStarCount)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(PiyoTheme.cheer.opacity(0.18)))

                    if let goal = environment.nextUnlockGoal {
                        Text("つぎは \(goal.name)")
                            .piyoFont(.caption)
                            .foregroundStyle(PiyoTheme.textSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }

            Spacer()

            Button {
                environment.haptics.tap()
                sheetRoute = .parentGate
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: CGFloat(layout.fontSize(19)), weight: .bold))
                    Text("おうちのひと")
                        .piyoFont(size: 11, weight: .semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(PiyoTheme.textSoft)
                .frame(width: CGFloat(layout.sized(82)), height: CGFloat(layout.sized(60)))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(PiyoTheme.surfaceSunken)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(A11yID.homeParent)
        }
    }

    /// 主役のごはんタイマー。
    private var mealTimerHero: some View {
        BigButton(color: PiyoTheme.success, minHeight: CGFloat(layout.sized(220))) {
            environment.haptics.tap()
            fullScreenRoute = .meal
        } label: {
            HStack(spacing: CGFloat(layout.sized(16))) {
                if MealSceneView<EmptyView>.hasScenes(for: environment.mealCharacter) {
                    MealSceneView(character: environment.mealCharacter, activity: .resting, isPlaying: false,
                                  reduceAnimations: true, seed: 0) { _ in EmptyView() }
                        .frame(maxHeight: CGFloat(layout.sized(180)))
                        .clipShape(RoundedRectangle(cornerRadius: PiyoTheme.smallCornerRadius, style: .continuous))
                        .allowsHitTesting(false)
                } else {
                    CharacterArtView(character: environment.mealCharacter, mood: .happy,
                                     size: CGFloat(layout.artSized(150)))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: CGFloat(layout.fontSize(34)), weight: .bold))
                    Text("ごはんタイマー")
                        .piyoFont(.title)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("\(environment.mealCharacter.name)と いっしょに たべよう")
                        .piyoFont(.body)
                        .opacity(0.92)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
        }
        .accessibilityIdentifier(A11yID.homeMealTimer)
    }

    /// ごはんタイマー以外。目立たせないよう、小さく控えめな色でまとめる。
    private var otherMenus: some View {
        VStack(alignment: .leading, spacing: CGFloat(layout.sized(8))) {
            Text("ほかの あそび")
                .piyoFont(.caption)
                .foregroundStyle(PiyoTheme.textSoft)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: CGFloat(layout.sized(8))), count: 3),
                spacing: CGFloat(layout.sized(8))
            ) {
                smallMenuButton(systemImage: "sparkles", title: "チャレンジ", action: startDailyChallenge)
                    .accessibilityIdentifier(A11yID.homeDailyChallenge)

                ForEach(Array(environment.settings.enabledSubjects).sorted(by: { $0.rawValue < $1.rawValue })) { subject in
                    smallMenuButton(systemImage: icon(for: subject), title: subject.childTitle) {
                        environment.haptics.tap()
                        environment.speak(subject.childTitle)
                        sheetRoute = .subjectMenu(subject)
                    }
                    .accessibilityIdentifier("\(A11yID.homeSubject)\(subject.rawValue)")
                }

                smallMenuButton(systemImage: "books.vertical.fill", title: "ずかん") {
                    environment.haptics.tap()
                    sheetRoute = .collection
                }
                .accessibilityIdentifier(A11yID.homeCollection)
            }
        }
    }

    private func smallMenuButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: CGFloat(layout.fontSize(20)), weight: .bold))
                Text(title)
                    .piyoFont(size: 13, weight: .semibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .foregroundStyle(PiyoTheme.textSoft)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(76)))
            .background(
                RoundedRectangle(cornerRadius: PiyoTheme.smallCornerRadius, style: .continuous)
                    .fill(PiyoTheme.surface.opacity(0.8))
            )
        }
        .buttonStyle(.plain)
    }

    private func icon(for subject: Subject) -> String {
        switch subject {
        case .clock: return "clock.fill"
        case .hiragana: return "character.book.closed.fill"
        case .katakana: return "textformat"
        case .number: return "number"
        case .alphabet: return "a.circle.fill"
        case .englishWord: return "globe"
        }
    }

    // MARK: - 操作

    private func startDailyChallenge() {
        environment.haptics.tap()
        let challenge = environment.makeDailyChallenge()
        guard !challenge.questions.isEmpty else { return }
        fullScreenRoute = .session(
            SessionRequest(kind: .dailyChallenge, subject: nil, questions: challenge.questions)
        )
    }

    private func startFreePlay(skill: Skill) {
        let questions = environment.makeFreePlayQuestions(skill: skill)
        guard !questions.isEmpty else { return }
        fullScreenRoute = .session(
            SessionRequest(kind: .freePlay, subject: skill.subject, questions: questions)
        )
    }

    /// ゲートを通ったあとで保護者画面を開く。
    /// 広告はここでだけ出す。ゲートの向こう側なので、見るのは必ず大人になる。
    ///
    /// 広告はルートに重ねて出すので、シートを先に開くとその下に隠れてしまう。
    /// 「ゲート → 広告 → 保護者画面」の順に、ひとつずつ出す。
    private func openParentArea() {
        guard environment.adPresenter.shouldPresentParentAd(adsRemoved: environment.settings.adsRemoved) else {
            sheetRoute = .parentArea
            return
        }
        environment.adPresenter.markParentAdPresented()
        opensParentAreaAfterAd = true
        environment.isShowingParentAd = true
    }

    private func greet() {
        guard let profile = environment.profile else { return }
        environment.speak("\(profile.callName)、こんにちは！ なにで あそぶ？")
    }

    /// 別の表示を閉じ切ってから次を出す。
    private func presentAfterDismiss(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            action()
        }
    }

    private func showNextUnlockIfNeeded() {
        guard !environment.pendingUnlocks.isEmpty else { return }
        unlockQueue.append(contentsOf: environment.consumePendingUnlocks())
    }
}
