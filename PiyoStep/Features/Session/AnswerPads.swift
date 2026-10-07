import SwiftUI
import PiyoCore

/// タップで選ぶ回答。
struct ChoiceGridView: View {
    @Bindable var model: SessionViewModel
    @Environment(\.piyoLayout) private var layout

    private var columns: [GridItem] {
        let spacing = CGFloat(layout.sized(14))
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: 2)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(Array(model.visibleChoices.enumerated()), id: \.element.id) { index, choice in
                ChoiceCardButton(
                    isHighlighted: model.selectedChoiceID == choice.id,
                    highlightColor: PiyoTheme.primary
                ) {
                    model.select(choice: choice)
                } content: {
                    choiceContent(choice)
                        .padding(12)
                }
                .accessibilityIdentifier("\(A11yID.sessionChoice)\(index)")
                .accessibilityLabel(choice.spokenText)
            }
        }
    }

    @ViewBuilder
    private func choiceContent(_ choice: AnswerChoice) -> some View {
        switch choice.display {
        case .text(let text):
            Text(text)
                .piyoFont(size: 52, weight: .heavy)
                .foregroundStyle(PiyoTheme.text)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        case .number(let value):
            Text("\(value)")
                .piyoFont(size: 52, weight: .heavy)
                .foregroundStyle(PiyoTheme.text)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
        case .clock(let time):
            VStack(spacing: 4) {
                MiniClockView(time: time, size: 76)
                Text(time.displayJapanese)
                    .piyoFont(.caption)
                    .foregroundStyle(PiyoTheme.textSoft)
            }
        case .object(let kind, let count):
            CountableObjectsView(kind: kind, count: count, maximumColumns: 5, itemSize: 24)
        case .picture(let card):
            EnglishWordIllustration(card: card, size: 76, showsText: false)
        case .kanaWord(let card, let subject):
            KanaWordIllustration(card: card, subject: subject, size: 70, showsWord: false)
        }
    }
}

/// 数字入力のキーパッド。
struct NumberPadView: View {
    @Bindable var model: SessionViewModel
    @Environment(\.piyoLayout) private var layout

    private let digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        VStack(spacing: 14) {
            Text(model.numberInput.isEmpty ? "—" : model.numberInput)
                .piyoFont(size: 56, weight: .heavy)
                .foregroundStyle(PiyoTheme.text)
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(84)))
                .background(
                    RoundedRectangle(cornerRadius: PiyoTheme.smallCornerRadius)
                        .fill(PiyoTheme.surface)
                )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(digits, id: \.self) { digit in
                    digitButton(digit)
                }
                clearButton
                digitButton(0)
                submitButton
            }
        }
    }

    private func digitButton(_ digit: Int) -> some View {
        Button {
            model.appendDigit(digit)
        } label: {
            Text("\(digit)")
                .piyoFont(size: 36, weight: .heavy)
                .foregroundStyle(PiyoTheme.text)
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(72)))
                .background(
                    RoundedRectangle(cornerRadius: 18).fill(PiyoTheme.surface)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(A11yID.sessionNumberPadDigit)\(digit)")
    }

    private var clearButton: some View {
        Button {
            model.clearInput()
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(PiyoTheme.textSoft)
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(72)))
                .background(RoundedRectangle(cornerRadius: 18).fill(PiyoTheme.surfaceSunken))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.sessionNumberPadClear)
    }

    private var submitButton: some View {
        Button {
            model.submitNumberInput()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(72)))
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(model.numberInput.isEmpty ? PiyoTheme.outline : PiyoTheme.success)
                )
        }
        .buttonStyle(.plain)
        .disabled(model.numberInput.isEmpty)
        .accessibilityIdentifier(A11yID.sessionNumberPadSubmit)
    }
}

/// 時刻を数字で入力するパッド（○じ ○ふん）。
struct TimePadView: View {
    @Bindable var model: SessionViewModel
    @Environment(\.piyoLayout) private var layout

    private let digits = [1, 2, 3, 4, 5, 6, 7, 8, 9]

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                slot(text: model.hourInput, unit: "じ", field: .hour)
                slot(text: model.minuteInput, unit: "ふん", field: .minute)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ForEach(digits, id: \.self) { digit in
                    digitButton(digit)
                }
                clearButton
                digitButton(0)
                submitButton
            }
        }
    }

    private func slot(text: String, unit: String, field: SessionViewModel.TimeField) -> some View {
        Button {
            model.activeTimeField = field
        } label: {
            HStack(spacing: 4) {
                Text(text.isEmpty ? "—" : text)
                    .piyoFont(size: 44, weight: .heavy)
                    .foregroundStyle(PiyoTheme.text)
                Text(unit)
                    .piyoFont(.body)
                    .foregroundStyle(PiyoTheme.textSoft)
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(84)))
            .background(
                RoundedRectangle(cornerRadius: PiyoTheme.smallCornerRadius)
                    .fill(PiyoTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: PiyoTheme.smallCornerRadius)
                            .stroke(
                                model.activeTimeField == field ? PiyoTheme.primary : PiyoTheme.outline,
                                lineWidth: model.activeTimeField == field ? 5 : 2
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func digitButton(_ digit: Int) -> some View {
        Button {
            model.appendDigit(digit)
        } label: {
            Text("\(digit)")
                .piyoFont(size: 36, weight: .heavy)
                .foregroundStyle(PiyoTheme.text)
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(72)))
                .background(RoundedRectangle(cornerRadius: 18).fill(PiyoTheme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(A11yID.sessionNumberPadDigit)\(digit)")
    }

    private var clearButton: some View {
        Button {
            model.clearInput()
        } label: {
            Image(systemName: "delete.left.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(PiyoTheme.textSoft)
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(72)))
                .background(RoundedRectangle(cornerRadius: 18).fill(PiyoTheme.surfaceSunken))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.sessionNumberPadClear)
    }

    private var submitButton: some View {
        Button {
            model.submitTimeInput()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(72)))
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(model.hourInput.isEmpty ? PiyoTheme.outline : PiyoTheme.success)
                )
        }
        .buttonStyle(.plain)
        .disabled(model.hourInput.isEmpty)
        .accessibilityIdentifier(A11yID.sessionNumberPadSubmit)
    }
}

/// 時計の針を動かして答える。
struct ClockDragPanel: View {
    @Bindable var model: SessionViewModel
    @Environment(\.piyoLayout) private var layout
    /// 時計の直径。指定が無ければ画面の形からの既定値。
    var clockSide: CGFloat?
    /// 「できた！」を時計の横に置くか（横向きで、高さを時計に使い切るとき）。
    var placesButtonsBeside = false

    private var minuteStep: Int {
        if case let .clockSet(_, _, step) = model.currentQuestion?.content { return step }
        return 5
    }

    var body: some View {
        if placesButtonsBeside {
            HStack(alignment: .center, spacing: 16) {
                clock
                VStack(spacing: 12) {
                    currentTimeLabel
                    submitButton
                }
                .frame(width: TracePanel.besideButtonsWidth + 24)
            }
        } else {
            VStack(spacing: 16) {
                clock
                currentTimeLabel
                submitButton
            }
        }
    }

    private var clock: some View {
        AnalogClockView(
            time: model.draggedTime,
            isInteractive: true,
            minuteStep: minuteStep,
            size: clockSide ?? CGFloat(layout.artSized(260)),
            onChange: { model.draggedTime = $0 },
            onStep: { model.clockHandStepped() },
            onTouchingChange: { model.isTouchingCanvas = $0 }
        )
    }

    private var currentTimeLabel: some View {
        Text("いま \(model.draggedTime.displayJapanese)")
            .piyoFont(.headline)
            .foregroundStyle(PiyoTheme.textSoft)
            .minimumScaleFactor(0.6)
            .lineLimit(2)
            .multilineTextAlignment(.center)
    }

    private var submitButton: some View {
        BigButton(color: PiyoTheme.success, action: { model.submitDraggedTime() }) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                Text("できた！")
                    .piyoFont(.headline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
        .accessibilityIdentifier(A11yID.sessionClockSubmit)
    }
}

/// なぞり書き・自由書き。
struct TracePanel: View {
    @Bindable var model: SessionViewModel
    @Environment(\.piyoLayout) private var layout

    private var templateText: String {
        guard let question = model.currentQuestion else { return "" }
        return AnswerGrader.correctAnswerDisplay(for: question)
    }

    private var showsTemplate: Bool {
        guard let question = model.currentQuestion else { return true }
        switch question.content {
        case .kanaCard(_, let task), .alphabetCard(_, let task, _):
            return task == .trace
        default:
            return true
        }
    }

    /// 書く欄の一辺。指定が無ければ画面の形からの既定値。
    var canvasSide: CGFloat?
    /// 「けす」「できた！」を書く欄の横に置くか（横向きで、高さを書く欄に使い切るとき）。
    var placesButtonsBeside = false

    var body: some View {
        if placesButtonsBeside {
            HStack(alignment: .center, spacing: 12) {
                canvas
                VStack(spacing: 12) {
                    clearButton
                    submitButton
                }
                .frame(width: TracePanel.besideButtonsWidth)
            }
        } else {
            VStack(spacing: 14) {
                canvas
                HStack(spacing: 12) {
                    clearButton
                    submitButton
                }
            }
        }
    }

    /// 横に置くときのボタンの幅。
    static let besideButtonsWidth: CGFloat = 132

    private var canvas: some View {
        TraceCanvasView(
            character: templateText,
            showsTemplate: showsTemplate,
            canvasSize: canvasSide ?? CGFloat(layout.artSized(280)),
            strokes: $model.traceStrokes,
            onTouchingChange: { model.isTouchingCanvas = $0 }
        )
    }

    private var clearButton: some View {
        Button {
            model.traceStrokes = []
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                Text("けす")
                    .piyoFont(.body)
            }
            .foregroundStyle(PiyoTheme.textSoft)
            .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(72)))
            .background(RoundedRectangle(cornerRadius: 18).fill(PiyoTheme.surfaceSunken))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.sessionTraceClear)
    }

    private var submitButton: some View {
        BigButton(
            color: PiyoTheme.success,
            minHeight: CGFloat(layout.sized(72)),
            isEnabled: !model.traceStrokes.isEmpty,
            action: { model.submitTrace() }
        ) {
            Text("できた！")
                .piyoFont(.headline)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .accessibilityIdentifier(A11yID.sessionTraceSubmit)
    }
}

/// 音声で答える。マイク・波形・キャラクターの反応をまとめる。
struct VoiceAnswerPanel: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.piyoLayout) private var layout
    @Bindable var model: SessionViewModel

    private var isListening: Bool {
        model.voiceState.isListening
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                CharacterArtView(
                    character: environment.buddyCharacter,
                    mood: isListening ? .listening : .idle,
                    size: 84
                )
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.voiceGuidanceText)
                        .piyoFont(.headline)
                        .foregroundStyle(PiyoTheme.text)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .accessibilityIdentifier(A11yID.sessionVoiceStatus)
                    if !model.voiceTranscript.isEmpty {
                        Text(model.voiceTranscript)
                            .piyoFont(.caption)
                            .foregroundStyle(PiyoTheme.textSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            VoiceWaveformView(level: model.voiceLevel, isListening: isListening)

            micButton

            if model.shouldSuggestTapAnswer {
                Button {
                    model.answerMode = .choice
                    model.stopVoice()
                } label: {
                    Text("タップで こたえる")
                        .piyoFont(.body)
                        .foregroundStyle(PiyoTheme.primaryDeep)
                        .frame(maxWidth: .infinity, minHeight: CGFloat(layout.sized(64)))
                        .background(Capsule().fill(PiyoTheme.primary.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// マイクは指で押すものなので、狭い画面でも小さくしすぎない。
    private var micSize: CGFloat { CGFloat(max(120, layout.artSized(132))) }

    private var micButton: some View {
        Button {
            if isListening {
                model.stopVoice()
            } else {
                model.startVoice()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isListening ? PiyoTheme.primaryDeep : PiyoTheme.primary)
                    .frame(width: micSize, height: micSize)
                    .shadow(color: PiyoTheme.primary.opacity(0.45), radius: isListening ? 24 : 12, y: 6)
                if isListening {
                    Circle()
                        .stroke(PiyoTheme.primary.opacity(0.45), lineWidth: 8)
                        .frame(width: micSize + CGFloat(model.voiceLevel) * 60, height: micSize + CGFloat(model.voiceLevel) * 60)
                        .animation(.easeOut(duration: 0.18), value: model.voiceLevel)
                }
                Image(systemName: isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(height: micSize * 1.33)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.sessionVoiceButton)
        .accessibilityLabel(isListening ? "きいているよ" : "マイク")
    }
}
