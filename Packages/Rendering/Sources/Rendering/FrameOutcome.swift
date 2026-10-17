/// The result of one frame of the render engine.
struct FrameOutcome: Sendable {
    /// `true` if the frame had work and drew.
    let didDraw: Bool
    /// `true` if the renderer needs another frame, for example for a build.
    let needsMore: Bool
}
