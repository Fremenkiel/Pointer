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
    /// The text boxes of a load with their layouts, made off the render thread (D-92).
    var laidOutText: [TextStore.LaidOut] = []
    /// The loads whose layouts run off the render thread.
    var textLoadsInFlight = 0
    /// The changes of the text boxes, in order.
    var textEdits: [TextEdit] = []
    /// The cards of a load with their title layouts, made off the render thread (D-92).
    var laidOutCards: [CardStore.LaidOut] = []
    /// The number of cards that the waiting card load reserves room for, or `nil`.
    var cardReserve: Int?
    /// The loads whose title layouts run off the render thread.
    var cardLoadsInFlight = 0
    /// The changes of the cards, in order.
    var cardEdits: [CardEdit] = []
    /// The previews that the loader decoded and no frame took yet (D-97).
    var decodedPreviews: [DecodedPreview] = []
    /// The newest request of a preview of this canvas that no frame took yet (D-97).
    var previewRender: PreviewRenderRequest?
    /// An open or a leave that starts, or `nil` (D-98).
    var transitionStart: TransitionStart?
    /// The newest weight of the parent image of a transition, or `nil` without a change.
    var transitionWeight: Double?
    /// `true` after the end of a transition that no frame took yet.
    var endsTransition = false
    /// The newest state of a pinch-out exit, or `nil` without a change (CARD-05).
    var pinchExit: PinchExit?
    /// `true` after the end of a pinch-out exit that no frame took yet.
    var endsPinchExit = false
    /// A flight of the camera that starts, or `nil` (D-121).
    var flight: RenderFlight?
    /// `true` after a camera from the main thread, which ends a flight (D-121).
    var endsFlight = false
    /// `true` while the render thread plays a flight that did not reach its end. A frame then
    /// does not wait for a camera from the main thread (D-121).
    var isFlying = false
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
    /// The new state of the eraser tool, or `nil` without a change. The mask texture exists only
    /// while the eraser is the tool (D-78).
    var eraserReady: Bool?
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
            || !laidOutText.isEmpty || !textEdits.isEmpty
            || !laidOutCards.isEmpty || !cardEdits.isEmpty || !decodedPreviews.isEmpty
            || previewRender != nil || transitionStart != nil || transitionWeight != nil
            || endsTransition || pinchExit != nil || endsPinchExit || flight != nil
            || !eraserSamples.isEmpty
            || endsEraser || eraserReady != nil
    }

    /// Moves the waiting preview render request out, or returns `nil` (D-131).
    mutating func takePreviewRender() -> PreviewRenderRequest? {
        defer { previewRender = nil }
        return previewRender
    }

    /// Moves the waiting changes out. The camera stays as the newest value.
    mutating func take() -> RenderInput {
        precondition(edits.isEmpty || editHandoff > 0, "Edits need a handoff number")
        let input = RenderInput(
            camera: hasNewCamera ? camera : nil,
            viewport: viewport,
            loaded: loaded,
            laidOutText: laidOutText,
            textLoadsInFlight: textLoadsInFlight,
            textEdits: textEdits,
            laidOutCards: laidOutCards,
            cardReserve: cardReserve,
            cardLoadsInFlight: cardLoadsInFlight,
            cardEdits: cardEdits,
            decodedPreviews: decodedPreviews,
            previewRender: previewRender,
            transitionStart: transitionStart,
            transitionWeight: transitionWeight,
            endsTransition: endsTransition,
            pinchExit: pinchExit,
            endsPinchExit: endsPinchExit,
            flight: flight,
            endsFlight: endsFlight,
            edits: edits,
            editHandoff: editHandoff,
            editsWantCompletion: editsWantCompletion,
            eraserStart: eraserStart,
            eraserSamples: eraserSamples,
            endsEraser: endsEraser,
            eraserReady: eraserReady,
            observer: observer
        )
        reset()
        assert(!hasContentChange, "The inbox is empty after a take")
        return input
    }

    /// Empties the changes that a frame took. The camera stays as the newest value.
    private mutating func reset() {
        eraserStart = nil
        eraserSamples = spareEraserSamples
        spareEraserSamples = []
        endsEraser = false
        eraserReady = nil
        cameraMovedInLastFrame = hasNewCamera
        hasNewCamera = false
        viewport = nil
        loaded = []
        laidOutText = []
        textEdits = []
        laidOutCards = []
        cardReserve = nil
        cardEdits = []
        decodedPreviews = []
        previewRender = nil
        transitionStart = nil
        transitionWeight = nil
        endsTransition = false
        pinchExit = nil
        endsPinchExit = false
        flight = nil
        endsFlight = false
        edits = []
        editHandoff = 0
        editsWantCompletion = false
    }
}
