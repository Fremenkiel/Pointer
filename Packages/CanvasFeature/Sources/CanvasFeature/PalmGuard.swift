import Foundation

/// Keeps a resting palm away from the finger gestures (architecture.md 4.1, review A-14).
///
/// The finger gestures ignore a touch that begins while the pencil touches, shortly after the
/// pencil lifts, or with a contact radius of a palm. A finger never draws in any case (TOOL-03).
struct PalmGuard {
    /// The time after a pencil lift in which a new finger touch is a palm. A start value.
    /// Tune it on a device.
    static let pencilCooldown: TimeInterval = 0.150
    /// A touch with a larger `majorRadius`, in points, is a palm. A start value: a fingertip
    /// gives about 10 points. Tune it on a device in M2.
    static let palmRadius = 30.0

    private var pencilTouches = 0
    private var lastPencilEnd: TimeInterval?

    /// `true` while a pencil touches the screen (D-36).
    var isPencilDown: Bool { pencilTouches > 0 }

    /// Records a pencil touch that began.
    mutating func pencilBegan() {
        pencilTouches += 1
    }

    /// Records a pencil touch that ended or was cancelled.
    mutating func pencilEnded(at time: TimeInterval) {
        pencilTouches = max(0, pencilTouches - 1)
        lastPencilEnd = time
    }

    /// Returns `true` if a finger touch that began at `time` with `majorRadius` can move the
    /// camera.
    func allowsFingerTouch(at time: TimeInterval, majorRadius: Double) -> Bool {
        guard !isPencilDown else { return false }
        if let lastPencilEnd, time - lastPencilEnd < Self.pencilCooldown {
            return false
        }
        return majorRadius <= Self.palmRadius
    }
}
