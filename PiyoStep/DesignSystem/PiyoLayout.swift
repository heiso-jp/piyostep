import SwiftUI
import PiyoCore

private struct PiyoLayoutKey: EnvironmentKey {
    static let defaultValue: LayoutMetrics = .default
}

extension EnvironmentValues {
    /// いまの画面の形から決まる寸法。`PiyoLayoutReader` が入れる。
    var piyoLayout: LayoutMetrics {
        get { self[PiyoLayoutKey.self] }
        set { self[PiyoLayoutKey.self] = newValue }
    }
}

/// 実際に与えられた大きさから寸法を決めて、下の View へ配る。
/// 端末名ではなく実寸で決めるので、分割表示でも回転でも正しく追従する。
///
/// 測った値は置いた View 自身の `@Environment(\.piyoLayout)` には返ってこないので、
/// 自分で値を見たいときは引数つきのクロージャを使う。
struct PiyoLayoutReader<Content: View>: View {
    private let content: (LayoutMetrics) -> Content

    init(@ViewBuilder content: @escaping (LayoutMetrics) -> Content) {
        self.content = content
    }

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = { _ in content() }
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = LayoutCalculator.metrics(
                width: Double(proxy.size.width),
                height: Double(proxy.size.height)
            )
            content(metrics)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(\.piyoLayout, metrics)
        }
    }
}

extension View {
    /// 本文の幅を、画面の形に合わせて制限して中央に置く。
    func piyoContentWidth(_ metrics: LayoutMetrics) -> some View {
        frame(maxWidth: CGFloat(metrics.contentMaxWidth))
            .frame(maxWidth: .infinity)
    }
}

// MARK: - 文字

/// 役割ごとの文字。大きさは画面の形で変わる。
enum PiyoFontRole {
    case giant
    case title
    case headline
    case body
    case caption

    var baseSize: Double {
        switch self {
        case .giant: return 110
        case .title: return 34
        case .headline: return 26
        case .body: return 20
        case .caption: return 16
        }
    }

    var weight: Font.Weight {
        switch self {
        case .giant: return .heavy
        case .title, .headline: return .bold
        case .body: return .semibold
        case .caption: return .medium
        }
    }
}

private struct PiyoFontModifier: ViewModifier {
    @Environment(\.piyoLayout) private var layout

    let size: Double
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(PiyoTheme.childFont(size: CGFloat(layout.fontSize(size)), weight: weight))
    }
}

extension View {
    /// 画面の形に合わせて大きさが変わる文字。
    func piyoFont(_ role: PiyoFontRole) -> some View {
        modifier(PiyoFontModifier(size: role.baseSize, weight: role.weight))
    }

    /// 大きさを直接指定する版。
    func piyoFont(size: Double, weight: Font.Weight = .bold) -> some View {
        modifier(PiyoFontModifier(size: size, weight: weight))
    }
}

// MARK: - キーボード

/// 文字入力中に、キーボードの上へ「かんりょう」を出す。
///
/// 横向きではキーボードが画面の半分以上を覆い、その下のボタンに手が届かない。
/// 閉じる手段を必ず用意しておく。
struct KeyboardDoneButton: ViewModifier {
    @FocusState.Binding var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit { isFocused = false }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("かんりょう") { isFocused = false }
                        .accessibilityIdentifier(A11yID.keyboardDone)
                }
            }
    }
}

extension View {
    /// 入力欄に付けると、キーボードの上に「かんりょう」が出る。
    func keyboardDoneButton(isFocused: FocusState<Bool>.Binding) -> some View {
        modifier(KeyboardDoneButton(isFocused: isFocused))
    }
}
