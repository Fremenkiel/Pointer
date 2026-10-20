import Geometry
import Model

/// The changes that the main actor sends to the render thread, and the state that the render
/// thread sends back (D-42). Only values cross between the threads.
struct RenderInbox {
    /// The newest camera.
    var camera = Camera(center: .zero, zoom: Limits.standardZoom)
    /// `true` after a camera change that no frame took yet.
    var hasNewCamera = false
    /// The newest view size and display scale that no frame took yet.
    var viewport: (size: Size, scale: Double)?
    /// Strokes to load without a handoff.
    var loaded: [Stroke] = []
    /// The edits of handoffs, erases, undo steps, and redo steps, in order.
    var edits: [RenderEdit] = []
    /// The number of the newest handoff in `edits`, or 0.
    var editHandoff: UInt64 = 0
    /// `true` if an edit in `edits` asks for the GPU end of its frame (P-08).
    var editsWantCompletion = false
    /// The radius in view points of an eraser gesture that starts, or `nil`.
    var eraserStart: Double?
    /// The eraser samples in view space that no frame took yet.
    var eraserSamples: [Point] = []
    /// The sample list that the last frame gave back, kept for reuse (PERF-01).
    var spareEraserSamples: [Point] = []
    /// `true` after the end of an eraser gesture that no frame took yet.
    var endsEraser = false
    /// `true` if the last frame took a new camera, so the camera is likely in motion.
    var cameraMovedInLastFrame = false
    /// `true` while the render thread waits for the camera of the current display frame.
    var isWaitingForCamera = false
    /// `true` while the frame loop sleeps. The next change wakes it.
    var isSleeping = false
    /// Wakes the frame loop. The render thread sets it.
    var wake: (@Sendable () -> Void)?
    /// Watches each frame. Only the tests set it.
    var observer: (any FrameObserving)?

    /// The number of strokes in the renderer after the last frame.
    var strokeCount = 0
    /// `true` if the renderer needed more frames after the last frame.
    var rendererHasWork = false

    /// `true` if a change waits that needs a frame, other than a camera change.
    var hasContentChange: Bool {
        viewport != nil || !loaded.isEmpty || !edits.isEmpty || eraserStart != nil
            || !eraserSamples.isEmpty || endsEraser
    }

    /// Moves the waiting changes out. The camera stays as the newest value.
    mutating func take() -> RenderInput {
        precondition(edits.isEmpty || editHandoff > 0, "Edits need a handoff number")
        let input = RenderInput(
            camera: hasNewCamera ? camera : nil,
            viewport: viewport,
            loaded: loaded,
            edits: edits,
            editHandoff: editHandoff,
            editsWantCompletion: editsWantCompletion,
            eraserStart: eraserStart,
            eraserSamples: eraserSamples,
            endsEraser: endsEraser,
            observer: observer
        )
        eraserStart = nil
        eraserSamples = spareEraserSamples
        spareEraserSamples = []
        endsEraser = false
        cameraMovedInLastFrame = hasNewCamera
        hasNewCamera = false
        viewport = nil
        loaded = []
        edits = []
        editHandoff = 0
        editsWantCompletion = false
        assert(!hasContentChange, "The inbox is empty after a take")
        return input
    }
}
