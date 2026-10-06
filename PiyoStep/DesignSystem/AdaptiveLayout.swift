import SwiftUI
import PiyoCore

/// 画面の形（`LayoutMetrics`）から、並べ方を決めるための値。
extension LayoutMetrics {
    /// 左右 2 枚に分けたほうがよい形か。
    var isSideBySide: Bool { shape.isLandscape }

    /// 縦の余裕が少ないか。イラストやボタンを小さめにする判断に使う。
    var isCompactHeight: Bool { shape == .compactWide || shape == .compact }

    /// 1 枚で見せるときの、読みやすい最大幅。
    var columnMaxWidth: CGFloat { CGFloat(contentMaxWidth) }

    /// 大きな絵やボタンの寸法を、画面の形に合わせて縮める。
    func scaled(_ value: CGFloat, minimum: CGFloat? = nil) -> CGFloat {
        let scaled = value * CGFloat(min(artScale, 1))
        return max(minimum ?? value * 0.6, scaled)
    }
}

/// 縦長では上下に、横長では左右に並べる。
///
/// どちらの形でも中身はスクロールできるので、ボタンが画面の外に出たままになることがない。
struct AdaptivePanes<Leading: View, Trailing: View>: View {
    @Environment(\.piyoLayout) private var layout

    var spacing: CGFloat = 20
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if layout.isSideBySide {
            HStack(alignment: .top, spacing: spacing) {
                pane { leading }
                pane { trailing }
            }
        } else {
            ScrollView {
                VStack(spacing: spacing) {
                    leading
                    trailing
                }
                .frame(maxWidth: layout.columnMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
        }
    }

    private func pane<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // 入りきるときは縦の中央に置く。上詰めだと下が大きく余ってしまう。
                    .frame(minHeight: proxy.size.height, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 1 枚ものの画面。入りきるときは今までどおり中央に置き、
/// 入りきらない形（横向きなど）になったらスクロールできるようにする。
struct AdaptiveColumn<Content: View>: View {
    @Environment(\.piyoLayout) private var layout

    var spacing: CGFloat = 20
    var maxWidth: CGFloat?
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: spacing) {
                    content
                }
                .frame(maxWidth: maxWidth ?? layout.columnMaxWidth)
                .frame(maxWidth: .infinity)
                // 余裕があるときは Spacer() が効くように、最低でも画面の高さを確保する。
                .frame(minHeight: proxy.size.height)
            }
        }
    }
}
