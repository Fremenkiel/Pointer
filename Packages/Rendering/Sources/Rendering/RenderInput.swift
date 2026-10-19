import Geometry
import Model

/// The changes that one frame takes from the inbox.
struct RenderInput: Sendable {
    /// The new camera, or `nil` if it did not change.
    let camera: Camera?
    /// The new view size and display scale, or `nil`.
    let viewport: (size: Size, scale: Double)?
    /// Strokes to load.
    let loaded: [Stroke]
    /// The edits, in order.
    let edits: [RenderEdit]
    /// The newest handoff of `edits`, or 0.
    let editHandoff: UInt64
    /// The test observer.
    let observer: (any FrameObserving)?

    /// `true` if the frame has a change to draw.
    var hasChange: Bool { camera != nil || viewport != nil || !loaded.isEmpty || !edits.isEmpty }
}
