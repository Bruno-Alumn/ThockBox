import AppKit
import SwiftUI

/// Where a slider's value crosses a detent: every `step` from the bottom of
/// its range, plus the range's ends. Returns whether moving from `old` to
/// `new` crossed or reached one.
enum SliderDetents {
    static func crossed(from old: Double, to new: Double, in range: ClosedRange<Double>, step: Double) -> Bool {
        guard old != new else { return false }
        if new == range.lowerBound || new == range.upperBound { return true }
        let a = ((old - range.lowerBound) / step).rounded(.down)
        let b = ((new - range.lowerBound) / step).rounded(.down)
        // Landing exactly on a detent counts; so does passing one.
        return a != b || ((new - range.lowerBound) / step).truncatingRemainder(dividingBy: 1) == 0
    }
}

private struct SliderHaptics: ViewModifier {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    @State private var last: Double?

    func body(content: Content) -> some View {
        content.onChange(of: value) { new in
            defer { last = new }
            guard let last, SliderDetents.crossed(from: last, to: new, in: range, step: step) else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        .onAppear { last = value }
    }
}

extension View {
    /// A trackpad tap as the slider passes each `step`, like the notches on
    /// a physical knob (Force Touch trackpads only).
    func sliderHaptics<V: BinaryFloatingPoint>(_ value: V, in range: ClosedRange<V>, step: V) -> some View {
        modifier(SliderHaptics(value: Double(value),
                               range: Double(range.lowerBound)...Double(range.upperBound),
                               step: Double(step)))
    }
}
