import SwiftUI
import PiyoCore

/// ごはんの乗ったお皿。`fullness` が 1.0 で満杯、0.0 で完食。
struct PlateView: View {
    var fullness: Double
    var tablewareArtKey: String = "white"
    var size: CGFloat = 150
    var foodName: String = "ごはん"

    private var clampedFullness: Double {
        min(max(fullness, 0), 1)
    }

    private var plateColor: Color {
        switch tablewareArtKey {
        case "flower": return Color(red: 1.0, green: 0.90, blue: 0.94)
        case "star": return Color(red: 0.92, green: 0.95, blue: 1.0)
        case "rainbow": return Color(red: 0.95, green: 1.0, blue: 0.93)
        default: return .white
        }
    }

    var body: some View {
        ZStack {
            // お皿
            Ellipse()
                .fill(plateColor)
                .frame(width: size, height: size * 0.62)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 5)
            Ellipse()
                .stroke(PiyoTheme.outline, lineWidth: 3)
                .frame(width: size, height: size * 0.62)
            Ellipse()
                .stroke(decorationColor, lineWidth: 5)
                .frame(width: size * 0.78, height: size * 0.48)

            // ごはん
            if clampedFullness > 0.02 {
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.87, blue: 0.62), Color(red: 0.96, green: 0.72, blue: 0.40)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // 残りの量にそのまま比例して縮める。平方根で縮めると減り始めがほとんど見えず、
                    // 長い時間の設定だと「ぜんぜん減っていない」ように見える。
                    .frame(
                        width: size * 0.62 * clampedFullness,
                        height: size * 0.38 * clampedFullness
                    )
                    .offset(y: -size * 0.02)
                    .animation(.easeInOut(duration: 0.5), value: clampedFullness)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.26))
                    .foregroundStyle(PiyoTheme.success)
                    .transition(.scale)
            }
        }
        .frame(width: size, height: size * 0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clampedFullness <= 0.02 ? "\(foodName)を たべおわった" : "\(foodName)が のこっている")
    }

    private var decorationColor: Color {
        switch tablewareArtKey {
        case "flower": return Color.pink.opacity(0.6)
        case "star": return PiyoTheme.calm.opacity(0.7)
        case "rainbow": return PiyoTheme.cheer.opacity(0.8)
        default: return PiyoTheme.outline.opacity(0.7)
        }
    }
}

/// キャラクターがどこまで食べ進んだかだけを見せる帯。
///
/// 子どもの進み具合は自分のお皿で分かるので、帯はキャラクターの分だけにして
/// 「追いかける相手」がはっきり見えるようにする。
struct CharacterProgressBar: View {
    var progress: Double
    var character: CharacterDefinition

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(character.name)
                .piyoFont(.caption)
                .foregroundStyle(PiyoTheme.textSoft)
            GeometryReader { proxy in
                let width = max(0, proxy.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PiyoTheme.surfaceSunken)
                    Capsule()
                        .fill(PiyoTheme.color(hex: character.accentColorHex).opacity(0.35))
                        .frame(width: width * clamped)
                    CharacterArtView(character: character, mood: .eating, size: 52, isAnimated: false)
                        .offset(x: max(0, min(width - 52, width * clamped - 26)))
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(PiyoTheme.textSoft)
                        .offset(x: max(0, width - 24))
                }
                .animation(.easeInOut(duration: 0.4), value: clamped)
            }
            .frame(height: 56)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(A11yID.mealCharacterProgress)
        .accessibilityLabel("\(character.name)は \(Int(clamped * 100))パーセント")
    }
}

/// 茶碗とごはん。経過に合わせてごはんの山が小さくなる。
///
/// 器の下端が枠の下端にそろうように置き、ごはんは器のふちの上に乗せる。
struct RiceBowlView: View {
    var fullness: Double
    var size: CGFloat = 150
    var foodName: String = "ごはん"

    private var clamped: Double { min(max(fullness, 0), 1) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .frame(width: size, height: size * 0.78)

            // ごはんの山。器のふちに乗せ、減るほど低くなる。
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.93, blue: 0.74),
                            Color(red: 0.95, green: 0.80, blue: 0.53)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(Ellipse().stroke(Color(red: 0.82, green: 0.66, blue: 0.42), lineWidth: 2))
                .frame(width: size * 0.72, height: size * 0.26 * clamped)
                .offset(y: -size * 0.47)
                .opacity(clamped > 0.02 ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: clamped)

            BowlShape()
                .fill(Color.white)
                .overlay(BowlShape().stroke(PiyoTheme.outline, lineWidth: 3))
                .frame(width: size, height: size * 0.5)

            if clamped <= 0.02 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: size * 0.22))
                    .foregroundStyle(PiyoTheme.success)
                    .offset(y: -size * 0.58)
                    .transition(.scale)
            }
        }
        .frame(width: size, height: size * 0.78, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(clamped <= 0.02 ? "\(foodName)を たべおわった" : "\(foodName)が のこっている")
    }
}

/// 下にすぼまった茶碗の形。
struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.18
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - inset, y: rect.maxY),
            control: CGPoint(x: rect.maxX - inset * 0.3, y: rect.maxY * 0.75)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + inset, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.maxY + rect.height * 0.22)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + inset * 0.3, y: rect.maxY * 0.75)
        )
        path.closeSubpath()
        return path
    }
}

/// 位（くらい）をブロックで見せる。
struct PlaceValueBlocksView: View {
    var value: Int
    var highlighted: NumberPlace? = nil
    var blockSize: CGFloat = 16

    private var breakdown: PlaceValueBreakdown {
        PlaceValueBreakdown(value: value)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 22) {
            if breakdown.hundreds > 0 {
                column(
                    title: NumberPlace.hundreds.childTitle,
                    count: breakdown.hundreds,
                    place: .hundreds
                ) {
                    AnyView(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PiyoTheme.calm)
                            .frame(width: blockSize * 3, height: blockSize * 3)
                            .overlay(
                                Grid3x3()
                                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                                    .frame(width: blockSize * 3, height: blockSize * 3)
                            )
                    )
                }
            }
            if breakdown.tens > 0 || breakdown.hundreds > 0 {
                column(title: NumberPlace.tens.childTitle, count: breakdown.tens, place: .tens) {
                    AnyView(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(PiyoTheme.success)
                            .frame(width: blockSize, height: blockSize * 3)
                    )
                }
            }
            column(title: NumberPlace.ones.childTitle, count: breakdown.ones, place: .ones) {
                AnyView(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PiyoTheme.primary)
                        .frame(width: blockSize, height: blockSize)
                )
            }
        }
    }

    private func column(
        title: String,
        count: Int,
        place: NumberPlace,
        @ViewBuilder block: @escaping () -> AnyView
    ) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 4) {
                if count == 0 {
                    Text("0")
                        .piyoFont(.body)
                        .foregroundStyle(PiyoTheme.textSoft)
                } else {
                    ForEach(0 ..< count, id: \.self) { _ in
                        block()
                    }
                }
            }
            .frame(minHeight: blockSize * 3, alignment: .bottom)
            Text(title)
                .piyoFont(size: 13, weight: .semibold)
                .foregroundStyle(highlighted == place ? PiyoTheme.primaryDeep : PiyoTheme.textSoft)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(highlighted == place ? PiyoTheme.cheer.opacity(0.25) : Color.clear)
        )
    }
}

struct Grid3x3: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1 ..< 3 {
            let x = rect.width / 3 * CGFloat(index)
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            let y = rect.height / 3 * CGFloat(index)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        return path
    }
}
