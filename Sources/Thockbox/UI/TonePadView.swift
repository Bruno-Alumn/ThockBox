import SwiftUI

/// 2D drag pad: x brightens/darkens (EQ tilt), y raises/lowers pitch.
/// Values are in -1...1 with (0, 0) at the center.
struct TonePadView: View {
    @Binding var x: Float
    @Binding var y: Float

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.thockTeal.opacity(0.14))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.thockTeal.opacity(0.35), lineWidth: 1)
                // Center crosshair
                Path { p in
                    p.move(to: CGPoint(x: size.width / 2, y: 4))
                    p.addLine(to: CGPoint(x: size.width / 2, y: size.height - 4))
                    p.move(to: CGPoint(x: 4, y: size.height / 2))
                    p.addLine(to: CGPoint(x: size.width - 4, y: size.height / 2))
                }
                .stroke(Color.thockTeal.opacity(0.25), lineWidth: 1)
                Circle()
                    .fill(Color.thockCoral)
                    .frame(width: 14, height: 14)
                    .shadow(radius: 1)
                    .position(x: CGFloat(x + 1) / 2 * size.width,
                              y: CGFloat(1 - y) / 2 * size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        x = Float(min(max(value.location.x / size.width, 0), 1)) * 2 - 1
                        y = (1 - Float(min(max(value.location.y / size.height, 0), 1))) * 2 - 1
                    }
            )
        }
        // Arrow keys move the handle once the pad has keyboard focus.
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .left: x = Self.step(x, by: -0.1)
            case .right: x = Self.step(x, by: 0.1)
            case .up: y = Self.step(y, by: 0.1)
            case .down: y = Self.step(y, by: -0.1)
            @unknown default: break
            }
        }
        // VoiceOver: one control. Adjusting changes brightness; pitch has
        // its own actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tone")
        .accessibilityValue(Self.describe(x: x, y: y))
        .accessibilityHint("Adjust to change brightness. Use the actions to change pitch.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: x = Self.step(x, by: 0.1)
            case .decrement: x = Self.step(x, by: -0.1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Raise pitch") { y = Self.step(y, by: 0.1) }
        .accessibilityAction(named: "Lower pitch") { y = Self.step(y, by: -0.1) }
        .accessibilityAction(named: "Reset tone") {
            x = 0
            y = 0
        }
    }

    /// Moves a value by `delta`, kept in -1...1 and on a 0.1 grid so
    /// repeated steps land back exactly on 0.
    static func step(_ value: Float, by delta: Float) -> Float {
        (min(max(value + delta, -1), 1) * 10).rounded() / 10
    }

    /// What VoiceOver reads, e.g. "40% brighter, pitch 20% higher".
    static func describe(x: Float, y: Float) -> String {
        func part(_ v: Float, up: String, down: String) -> String? {
            let percent = Int((abs(v) * 100).rounded())
            guard percent > 0 else { return nil }
            return "\(percent)% \(v > 0 ? up : down)"
        }
        let tone = part(x, up: "brighter", down: "darker") ?? "neutral"
        let pitch = part(y, up: "higher", down: "lower").map { "pitch \($0)" } ?? "normal pitch"
        return "\(tone), \(pitch)"
    }
}
