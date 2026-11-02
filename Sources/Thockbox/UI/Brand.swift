import AppKit
import SwiftUI

/// The coral of the logo's center key and sound waves (#FF7952), from
/// art/logo-source.png. Everything else uses system colors.
extension Color {
    static let thockCoral = Color(red: 1, green: 0.475, blue: 0.322)
}

/// The menu bar icon: the logo's three keycaps on a diagonal with sound
/// waves, drawn as a template image so macOS tints it for light and dark
/// menu bars. When sounds are off the waves go away.
enum MenuBarIcon {
    static let on = make(soundsOn: true)
    static let off = make(soundsOn: false)

    private static func make(soundsOn: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: 35)
            transform.concat()

            NSColor.black.set()
            let key = NSSize(width: 3.6, height: 3.2)
            for offset in [-5.0, 0, 5.0] as [CGFloat] {
                let keyRect = NSRect(x: offset - key.width / 2, y: -key.height / 2,
                                     width: key.width, height: key.height)
                NSBezierPath(roundedRect: keyRect, xRadius: 0.8, yRadius: 0.8).fill()
            }
            if soundsOn {
                for (radius, sweep) in [(5.4, 30.0), (8.1, 26.0)] as [(CGFloat, CGFloat)] {
                    for start in [90.0, 270.0] as [CGFloat] {
                        let arc = NSBezierPath()
                        arc.appendArc(withCenter: .zero, radius: radius,
                                      startAngle: start - sweep, endAngle: start + sweep)
                        arc.lineWidth = 1.2
                        arc.lineCapStyle = .round
                        arc.stroke()
                    }
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = soundsOn ? "ThockBox, sounds on" : "ThockBox, sounds off"
        return image
    }
}
