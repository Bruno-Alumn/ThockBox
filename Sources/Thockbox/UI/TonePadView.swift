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
                    .fill(Color.secondary.opacity(0.12))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                // Center crosshair
                Path { p in
                    p.move(to: CGPoint(x: size.width / 2, y: 4))
                    p.addLine(to: CGPoint(x: size.width / 2, y: size.height - 4))
                    p.move(to: CGPoint(x: 4, y: size.height / 2))
                    p.addLine(to: CGPoint(x: size.width - 4, y: size.height / 2))
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                Circle()
                    .fill(Color.accentColor)
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
    }
}
