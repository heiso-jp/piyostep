import SwiftUI
import UIKit
import PiyoCore

/// 文字をラスタライズして「お手本マスク」をつくる。
/// 画像アセットを持たずに、どの文字でも なぞり書き判定ができる。
enum GlyphMaskRenderer {
    private static var cache: [String: GlyphMask] = [:]
    static let resolution = 56

    /// SwiftUI 側のお手本表示と同じ書体を使う。
    static func templateFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func mask(for text: String) -> GlyphMask {
        if let cached = cache[text] { return cached }
        let generated = render(text: text, resolution: resolution)
        cache[text] = generated
        return generated
    }

    private static func render(text: String, resolution: Int) -> GlyphMask {
        guard !text.isEmpty, resolution > 0 else {
            return GlyphMask(width: 0, height: 0, cells: [])
        }
        let canvasSize = CGSize(width: resolution, height: resolution)
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { _ in
            let font = UIFont.systemFont(ofSize: CGFloat(resolution) * 0.78, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.white
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let bounds = attributed.boundingRect(
                with: canvasSize,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            let origin = CGPoint(
                x: (canvasSize.width - bounds.width) / 2 - bounds.minX,
                y: (canvasSize.height - bounds.height) / 2 - bounds.minY
            )
            attributed.draw(at: origin)
        }

        guard let cgImage = image.cgImage else {
            return GlyphMask(width: 0, height: 0, cells: [])
        }

        var pixels = [UInt8](repeating: 0, count: resolution * resolution)
        let success: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: resolution,
                      height: resolution,
                      bitsPerComponent: 8,
                      bytesPerRow: resolution,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else {
                return false
            }
            context.draw(cgImage, in: CGRect(origin: .zero, size: canvasSize))
            return true
        }
        guard success else {
            return GlyphMask(width: 0, height: 0, cells: [])
        }

        let cells = pixels.map { $0 > 110 }
        return GlyphMask(width: resolution, height: resolution, cells: cells)
    }
}

/// なぞり書き・自由書きのキャンバス。
struct TraceCanvasView: View {
    /// なぞる文字
    var character: String
    /// お手本を薄く出すか（自由書きでは false）
    var showsTemplate: Bool = true
    var canvasSize: CGFloat = 280
    var strokeColor: Color = PiyoTheme.primary
    @Binding var strokes: [[TracePoint]]
    /// 指で触り始めた・離した。
    var onTouchingChange: ((Bool) -> Void)? = nil

    @State private var currentStroke: [TracePoint] = []

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PiyoTheme.cornerRadius, style: .continuous)
                .fill(PiyoTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: PiyoTheme.cornerRadius, style: .continuous)
                        .stroke(PiyoTheme.outline, lineWidth: 3)
                )

            // 十字のガイド
            Path { path in
                path.move(to: CGPoint(x: canvasSize / 2, y: 16))
                path.addLine(to: CGPoint(x: canvasSize / 2, y: canvasSize - 16))
                path.move(to: CGPoint(x: 16, y: canvasSize / 2))
                path.addLine(to: CGPoint(x: canvasSize - 16, y: canvasSize / 2))
            }
            .stroke(PiyoTheme.outline.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))

            if showsTemplate {
                Text(character)
                    .font(GlyphMaskRenderer.templateFont(size: canvasSize * 0.78))
                    .foregroundStyle(PiyoTheme.outline.opacity(0.85))
            }

            strokePaths
        }
        .frame(width: canvasSize, height: canvasSize)
        .contentShape(Rectangle())
        .highPriorityGesture(drawGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(A11yID.sessionTraceCanvas)
        .accessibilityLabel("「\(character)」を なぞる ところ")
    }

    private var strokePaths: some View {
        ZStack {
            ForEach(Array(strokes.enumerated()), id: \.offset) { _, stroke in
                path(for: stroke)
                    .stroke(
                        strokeColor,
                        style: StrokeStyle(lineWidth: canvasSize * 0.11, lineCap: .round, lineJoin: .round)
                    )
            }
            path(for: currentStroke)
                .stroke(
                    strokeColor,
                    style: StrokeStyle(lineWidth: canvasSize * 0.11, lineCap: .round, lineJoin: .round)
                )
        }
    }

    private func path(for stroke: [TracePoint]) -> Path {
        var path = Path()
        guard let first = stroke.first else { return path }
        path.move(to: point(first))
        if stroke.count == 1 {
            path.addLine(to: point(first))
        }
        for item in stroke.dropFirst() {
            path.addLine(to: point(item))
        }
        return path
    }

    private func point(_ tracePoint: TracePoint) -> CGPoint {
        CGPoint(x: tracePoint.x * canvasSize, y: tracePoint.y * canvasSize)
    }

    private var drawGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let normalized = TracePoint(
                    x: min(max(value.location.x / canvasSize, 0), 1),
                    y: min(max(value.location.y / canvasSize, 0), 1)
                )
                if currentStroke.isEmpty { onTouchingChange?(true) }
                currentStroke.append(normalized)
            }
            .onEnded { _ in
                if !currentStroke.isEmpty {
                    strokes.append(currentStroke)
                    currentStroke = []
                }
                onTouchingChange?(false)
            }
    }
}
