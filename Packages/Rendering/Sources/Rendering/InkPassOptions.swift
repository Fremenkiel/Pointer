import Foundation
import Metal

/// The options of one ink pass.
struct InkPassOptions {
    /// `true` clears the texture before the draw.
    let clear: Bool
    /// The pass stops after the stroke that reaches this number of instances.
    let instanceBudget: Int
    /// The pass stops after this `CACurrentMediaTime()` value, after its first stroke.
    var deadline: TimeInterval = .infinity
    /// The pixel rectangle that the pass draws into, or `nil` for the whole texture.
    var scissor: MTLScissorRect?
    /// `true` sets the pixels of `scissor` to zero before the draw (D-66).
    var clearsScissor = false
}
