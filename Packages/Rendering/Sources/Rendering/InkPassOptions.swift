import Foundation

/// The options of one ink pass.
struct InkPassOptions {
    /// `true` clears the texture before the draw.
    let clear: Bool
    /// The pass stops after the stroke that reaches this number of instances.
    let instanceBudget: Int
    /// The frame number, for the least-recently-drawn order of the arena.
    let frame: UInt64
    /// The pass stops after this `CACurrentMediaTime()` value, after its first stroke.
    var deadline: TimeInterval = .infinity
}
