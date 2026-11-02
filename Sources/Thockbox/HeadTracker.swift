import CoreMotion
import Foundation

/// Follows head movement from AirPods (and other headphones that report
/// it), so spatial keys stay where they are in the room when you turn your
/// head, like the system's own spatial audio. Where the head points when
/// tracking starts counts as straight ahead.
@available(macOS 14, *)
final class HeadTracker {
    private let manager = CMHeadphoneMotionManager()
    private var reference: CMAttitude?
    private let onTurn: (_ yaw: Float, _ pitch: Float) -> Void

    /// Called on the main queue with the listener's orientation in degrees.
    init(onTurn: @escaping (_ yaw: Float, _ pitch: Float) -> Void) {
        self.onTurn = onTurn
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }

    /// Starts following the head; the first reading becomes "ahead". Does
    /// nothing when no connected headphones report motion.
    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        reference = nil
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            guard let reference else {
                self.reference = attitude.copy() as? CMAttitude
                return
            }
            attitude.multiply(byInverseOf: reference)
            let turn = Self.listenerOrientation(yaw: attitude.yaw, pitch: attitude.pitch)
            onTurn(turn.yaw, turn.pitch)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        reference = nil
    }

    /// Head attitude (radians; Core Motion's yaw grows turning left) to the
    /// audio listener's orientation (degrees; AVAudio's yaw grows turning
    /// right), so the listener turns with the head and the keys stay put.
    static func listenerOrientation(yaw: Double, pitch: Double) -> (yaw: Float, pitch: Float) {
        (Float(-yaw * 180 / .pi), Float(pitch * 180 / .pi))
    }
}
