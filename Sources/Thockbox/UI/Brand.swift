import AppKit
import SwiftUI

/// Colors from the Thockbox logo (art/logo-source.png).
extension Color {
    /// Tile background, #00676D.
    static let thockTeal = Color(red: 0, green: 0.404, blue: 0.427)
    /// Center key and sound waves, #FF7952. Used as the app's accent.
    static let thockCoral = Color(red: 1, green: 0.475, blue: 0.322)
    /// Side keys, #FDF5EA.
    static let thockCream = Color(red: 0.992, green: 0.961, blue: 0.918)
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
        image.accessibilityDescription = soundsOn ? "Thockbox, sounds on" : "Thockbox, sounds off"
        return image
    }
}
