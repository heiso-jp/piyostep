import SwiftUI
import PiyoCore

/// 学習セッションの画面。出題・回答・フィードバック・結果をまとめる。
struct SessionView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.piyoLayout) private var layout

    let request: SessionRequest

    @State private var model: SessionViewModel?
    @State private var isShowingQuitConfirmation = false

    private var isShowingResult: Bool {
        model?.stage == .finished && model?.summary != nil
    }

    var body: some View {
        PiyoLayoutReader { _ in
            ZStack {
                PiyoBackground(tint: PiyoTheme.color(for: request.subject ?? .number))

                if let model {
                    sessionBody(model)
                }
            }
        }
        .accessibilityElement(children: .contain)
        // 入れ子のコンテナは潰れてしまうので、結果画面に変わったら名前も入れ替える。
        // こうしないと「いまどの画面か」が VoiceOver からも UI テストからも分からない。
        .accessibilityIdentifier(isShowingResult ? A11yID.result : A11yID.session)
        .onAppear {
            guard model == nil else { return }
            let created = SessionViewModel(
                environment: environment,
                kind: request.kind,
                subject: request.subject,
                questions: request.questions
            )
            created.start()
            model = created
        }
        .onDisappear {
            model?.close()
        }
        .confirmationDialog("やめる？", isPresented: $isShowingQuitConfirmation) {
            Button("ホームに もどる", role: .destructive) { dismiss() }
            Button("つづける", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func sessionBody(_ model: SessionViewModel) -> some View {
        if model.stage == .finished, let summary = model.summary {
            SessionResultView(summary: summary) {
                dismiss()
            }
        } else {
            VStack(spacing: 14) {
                header(model)
                if layout.usesSideBySideAnswer, model.answerMode == .trace || model.answerMode == .dragHands {
                    // 書く問題・針を動かす問題は、指で触る欄に画面の半分くらいを使う。
                    // 高さいっぱいの正方形にして、ボタンはその横に置く。
                    // スクロールの中に置くと、子どもの指が縦にぶれただけでスクロールに取られる。
                    GeometryReader { proxy in
                        let side = max(160, min(proxy.size.height, proxy.size.width * 0.5))
                        HStack(alignment: .center, spacing: CGFloat(layout.spacing)) {
                            ScrollView { questionArea(model).padding(.vertical, 4) }
                                .scrollDisabled(model.isTouchingCanvas)
                            Group {
                                if model.answerMode == .trace {
                                    TracePanel(model: model, canvasSide: side, placesButtonsBeside: true)
                                } else {
                                    ClockDragPanel(model: model, clockSide: side, placesButtonsBeside: true)
                                }
                            }
                            .disabled(model.stage == .feedback)
                            .opacity(model.stage == .feedback ? 0.4 : 1)
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .padding(.horizontal, CGFloat(layout.spacing))
                    .padding(.bottom, 16)
                } else if layout.usesSideBySideAnswer {
                    // 横向きは出題を左、回答を右に置く。縦に積むと、
                    // 高さ 390pt の iPhone 横持ちで回答ボタンが画面の外に出る。
                    HStack(alignment: .top, spacing: CGFloat(layout.spacing)) {
                        ScrollView { questionArea(model).padding(.vertical, 4) }
                            .scrollDisabled(model.isTouchingCanvas)
                        ScrollView { answerArea(model).padding(.vertical, 4) }
                            .scrollDisabled(model.isTouchingCanvas)
                    }
                    .padding(.horizontal, CGFloat(layout.spacing))
                    .padding(.bottom, 16)
                    .piyoContentWidth(layout)
                } else {
                    ScrollView {
                        VStack(spacing: CGFloat(layout.spacing)) {
                            questionArea(model)
                            answerArea(model)
                        }
                        .padding(.horizontal, CGFloat(layout.spacing))
                        .padding(.bottom, 28)
                        .piyoContentWidth(layout)
                    }
                    .scrollDisabled(model.isTouchingCanvas)
                }
            }
            .overlay(alignment: .bottom) {
                if model.stage == .feedback, let feedback = model.feedback {
                    FeedbackPanel(
                        feedback: feedback,
                        character: environment.buddyCharacter,
                        onRetry: { model.retryCurrentQuestion() },
                        onNext: { model.advance() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .overlay {
                ConfettiView(isActive: model.showsConfetti)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.stage)
        }
    }

    // MARK: - ヘッダー

    private func header(_ model: SessionViewModel) -> some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    isShowingQuitConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(PiyoTheme.textSoft)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(PiyoTheme.surface.opacity(0.9)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(A11yID.sessionClose)

                Spacer()

                Text("\(min(model.progressCount + 1, model.totalCount)) / \(model.totalCount)")
                    .piyoFont(.body)
                    .foregroundStyle(PiyoTheme.textSoft)

                Spacer()

                Button {
                    model.speakPrompt()
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PiyoTheme.textSoft)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(PiyoTheme.surface.opacity(0.9)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("もういちど きく")
            }
            SessionProgressBar(current: model.progressCount, total: model.totalCount)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - 出題

    private func questionArea(_ model: SessionViewModel) -> some View {
        VStack(spacing: 16) {
            Text(model.currentQuestion?.prompt.displayText ?? "")
                .piyoFont(.title)
                .foregroundStyle(PiyoTheme.text)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .accessibilityIdentifier(A11yID.sessionPrompt)

            if let question = model.currentQuestion {
                QuestionContentView(question: question, model: model)
            }

            if model.showsHint, let hint = model.currentQuestion?.prompt.hintText {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(PiyoTheme.cheer)
                    Text(hint)
                        .piyoFont(.body)
                        .foregroundStyle(PiyoTheme.textSoft)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(PiyoTheme.cheer.opacity(0.18)))
            }
        }
    }

    // MARK: - 回答

    @ViewBuilder
    private func answerArea(_ model: SessionViewModel) -> some View {
        VStack(spacing: 16) {
            if model.availableModes.count > 1 {
                AnswerModePicker(model: model)
            }

            switch model.answerMode {
            case .choice:
                ChoiceGridView(model: model)
            case .numberPad:
                if model.currentQuestion?.subject == .clock {
                    TimePadView(model: model)
                } else {
                    NumberPadView(model: model)
                }
            case .voice:
                VoiceAnswerPanel(model: model)
            case .dragHands:
                ClockDragPanel(model: model)
            case .trace:
                TracePanel(model: model)
            }
        }
        .disabled(model.stage == .feedback)
        .opacity(model.stage == .feedback ? 0.4 : 1)
    }
}

/// 回答方法の切り替え。アイコンで分かるようにする。
struct AnswerModePicker: View {
    @Bindable var model: SessionViewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.availableModes, id: \.self) { mode in
                Button {
                    model.answerMode = mode
                    model.stopVoice()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: icon(for: mode))
                            .font(.system(size: 22, weight: .bold))
                        Text(mode.childTitle)
                            .piyoFont(size: 13, weight: .semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(model.answerMode == mode ? .white : PiyoTheme.textSoft)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(model.answerMode == mode ? PiyoTheme.primary : PiyoTheme.surface)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(A11yID.sessionModePicker)\(mode.rawValue)")
            }
        }
    }

    private func icon(for mode: AnswerMode) -> String {
        switch mode {
        case .choice: return "hand.tap.fill"
        case .numberPad: return "number"
        case .voice: return "mic.fill"
        case .dragHands: return "hand.draw.fill"
        case .trace: return "pencil.tip"
        }
    }
}

/// 正解・不正解のフィードバック。
struct FeedbackPanel: View {
    let feedback: SessionFeedback
    let character: CharacterDefinition
    var onRetry: () -> Void
    var onNext: () -> Void

    private var tint: Color {
        switch feedback.judgement {
        case .correct: return PiyoTheme.success
        case .incorrect: return PiyoTheme.primary
        case .unclear: return PiyoTheme.calm
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                CharacterArtView(
                    character: character,
                    mood: feedback.judgement == .correct ? .happy : .cheering,
                    size: 80
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(feedback.message)
                        .piyoFont(.headline)
                        .foregroundStyle(PiyoTheme.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(3)
                        .accessibilityIdentifier(A11yID.sessionFeedback)

                    // 挑戦回数を使い切ったら、答えが分からないままにしない。
                    if feedback.revealsAnswer, !feedback.correctAnswerDisplay.isEmpty {
                        HStack(spacing: 8) {
                            Text("こたえは")
                                .piyoFont(.body)
                                .foregroundStyle(PiyoTheme.textSoft)
                            Text(feedback.correctAnswerDisplay)
                                .piyoFont(.headline)
                                .foregroundStyle(PiyoTheme.primaryDeep)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(PiyoTheme.cheer.opacity(0.24)))
                        .accessibilityIdentifier(A11yID.sessionAnswerReveal)
                    }
                    if feedback.starsEarned > 0 {
                        StarRewardView(stars: feedback.starsEarned, maximum: 2, size: 26)
                    }
                }
                Spacer(minLength: 0)
            }

            if feedback.canRetry {
                BigButton(color: tint, action: onRetry) {
                    Text("もういっかい！")
                        .piyoFont(.headline)
                }
                .accessibilityIdentifier(A11yID.sessionRetry)
            } else {
                BigButton(color: tint, action: onNext) {
                    HStack(spacing: 10) {
                        Text("つぎへ")
                            .piyoFont(.headline)
                        Image(systemName: "arrow.right")
                    }
                }
                .accessibilityIdentifier(A11yID.sessionNext)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: PiyoTheme.cornerRadius, style: .continuous)
                .fill(PiyoTheme.surface)
                .shadow(color: .black.opacity(0.14), radius: 20, y: -4)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: 720)
    }
}
