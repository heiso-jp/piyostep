import SwiftUI
import PiyoCore

/// アナログ時計。読み取り専用にも、針をドラッグできるようにもできる。
struct AnalogClockView: View {
    var time: ClockTime
    var isInteractive: Bool = false
    var minuteStep: Int = 5
    var showsNumbers: Bool = true
    var size: CGFloat = 280
    var onChange: ((ClockTime) -> Void)? = nil
    /// 針が 1 目盛り動いたとき（音・振動を出す）。
    var onStep: (() -> Void)? = nil
    /// 指で触り始めた・離した。
    var onTouchingChange: ((Bool) -> Void)? = nil

    @State private var hourAngle: Double = 0
    @State private var minuteAngle: Double = 0
    @State private var draggingHand: Hand?
    /// 最後に音・振動を出した時刻。同じ目盛りで何度も鳴らさない。
    @State private var lastSteppedTime: ClockTime?

    enum Hand {
        case hour
        case minute
    }

    /// 掴んでいる針は、目盛りに丸めずに指の位置へそのまま付いていく。
    /// 丸めた位置に描くと 5 分（30 度）ずつ飛び、指から離れて「動かない」ように見える。
    private var hourHandAngle: Double {
        draggingHand == .hour ? hourAngle : displayedTime.hourHandAngleDegrees
    }

    private var minuteHandAngle: Double {
        draggingHand == .minute ? minuteAngle : displayedTime.minuteHandAngleDegrees
    }

    /// 現在表示している時刻。
    private var displayedTime: ClockTime {
        guard isInteractive else { return time }
        return ClockTime.fromHandAngles(
            hourAngleDegrees: hourAngle,
            minuteAngleDegrees: minuteAngle,
            minuteStep: minuteStep
        )
    }

    var body: some View {
        ZStack {
            face
            ticks
            if showsNumbers { numbers }
            hand(
                length: size * 0.26,
                width: size * 0.045,
                angle: hourHandAngle,
                color: PiyoTheme.primaryDeep,
                identifier: A11yID.sessionClockHourHand
            )
            hand(
                length: size * 0.37,
                width: size * 0.032,
                angle: minuteHandAngle,
                color: PiyoTheme.calm,
                identifier: A11yID.sessionClockMinuteHand
            )
            Circle()
                .fill(PiyoTheme.text)
                .frame(width: size * 0.07)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .highPriorityGesture(dragGesture, including: isInteractive ? .all : .subviews)
        .onAppear(perform: syncAngles)
        .onChange(of: time) { _, _ in syncAngles() }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(A11yID.sessionClockFace)
        .accessibilityLabel(Text(displayedTime.displayJapanese))
    }

    // MARK: - 部品

    private var face: some View {
        ZStack {
            Circle()
                .fill(PiyoTheme.surface)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
            Circle()
                .stroke(PiyoTheme.primary.opacity(0.5), lineWidth: size * 0.03)
        }
    }

    private var ticks: some View {
        ForEach(0 ..< 60, id: \.self) { index in
            let isHour = index % 5 == 0
            Capsule()
                .fill(isHour ? PiyoTheme.textSoft : PiyoTheme.outline)
                .frame(width: isHour ? size * 0.012 : size * 0.006,
                       height: isHour ? size * 0.05 : size * 0.026)
                .offset(y: -size * 0.43)
                .rotationEffect(.degrees(Double(index) * 6))
        }
    }

    private var numbers: some View {
        ForEach(1 ... 12, id: \.self) { hour in
            let angle = Double(hour) * .pi / 6
            Text("\(hour)")
                .font(PiyoTheme.childFont(size: size * 0.11))
                .foregroundStyle(PiyoTheme.text)
                .offset(
                    x: CGFloat(sin(angle)) * size * 0.345,
                    y: CGFloat(-cos(angle)) * size * 0.345
                )
        }
    }

    private func hand(
        length: CGFloat,
        width: CGFloat,
        angle: Double,
        color: Color,
        identifier: String
    ) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: angle)
            .accessibilityIdentifier(identifier)
    }

    // MARK: - ドラッグ

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // CGFloat と Double が混ざると演算子の解決が曖昧になるので、
                // 角度の計算はすべて Double に寄せる。
                let center = CGPoint(x: size / 2, y: size / 2)
                let dx = Double(value.location.x - center.x)
                let dy = Double(value.location.y - center.y)
                let radius = (dx * dx + dy * dy).squareRoot()
                guard radius > Double(size) * 0.05 else { return }

                let angle = ClockTime.normalizeDegrees(atan2(dx, -dy) * 180.0 / .pi)

                if draggingHand == nil {
                    draggingHand = closestHand(to: angle, radius: radius)
                    lastSteppedTime = displayedTime
                    onTouchingChange?(true)
                    onStep?()
                }
                switch draggingHand {
                case .hour:
                    hourAngle = angle
                case .minute:
                    minuteAngle = angle
                case .none:
                    break
                }
                let current = displayedTime
                if current != lastSteppedTime {
                    // 目盛りをまたいだときだけ鳴らす。
                    lastSteppedTime = current
                    onStep?()
                }
                onChange?(current)
            }
            .onEnded { _ in
                // 指を離したら、丸められた位置に針をすっと揃える。
                let snapped = displayedTime
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    draggingHand = nil
                    hourAngle = snapped.hourHandAngleDegrees
                    minuteAngle = snapped.minuteHandAngleDegrees
                }
                lastSteppedTime = nil
                onTouchingChange?(false)
                onChange?(snapped)
            }
    }

    /// 触った場所に近いほうの針を掴む。
    private func closestHand(to angle: Double, radius: Double) -> Hand {
        let current = displayedTime
        let hourDelta = angularDistance(angle, current.hourHandAngleDegrees)
        let minuteDelta = angularDistance(angle, current.minuteHandAngleDegrees)

        // 外周に近いところを触ったら、長い針（分）を優先する。
        if radius > Double(size) * 0.30 {
            return minuteDelta < 50 ? .minute : (hourDelta < minuteDelta ? .hour : .minute)
        }
        return hourDelta <= minuteDelta ? .hour : .minute
    }

    private func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let diff = abs(ClockTime.normalizeDegrees(lhs) - ClockTime.normalizeDegrees(rhs))
        return min(diff, 360 - diff)
    }

    private func syncAngles() {
        hourAngle = time.hourHandAngleDegrees
        minuteAngle = time.minuteHandAngleDegrees
    }
}

/// 時計を小さく出すだけの表示（選択肢用）。
struct MiniClockView: View {
    var time: ClockTime
    var size: CGFloat = 76

    var body: some View {
        AnalogClockView(
            time: time,
            isInteractive: false,
            showsNumbers: false,
            size: size
        )
    }
}
