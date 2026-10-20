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
    /// `true` if an edit asks for the GPU end of its frame.
    let editsWantCompletion: Bool
    /// The radius in view points of an eraser gesture that starts, or `nil`.
    let eraserStart: Double?
    /// The new eraser samples in view space. The engine gives the list back for reuse.
    var eraserSamples: [Point]
    /// `true` if the eraser gesture ends.
    let endsEraser: Bool
    /// The new state of the eraser tool, or `nil` without a change (D-78).
    let eraserReady: Bool?
    /// The test observer.
    let observer: (any FrameObserving)?

    /// `true` if the frame has a change to draw.
    var hasChange: Bool {
        camera != nil || viewport != nil || !loaded.isEmpty || !edits.isEmpty
            || eraserStart != nil || !eraserSamples.isEmpty || endsEraser || eraserReady != nil
    }
}
