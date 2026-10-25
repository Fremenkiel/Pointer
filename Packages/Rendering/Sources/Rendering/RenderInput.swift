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
    /// The text boxes of a load with their layouts (D-92).
    let laidOutText: [TextStore.LaidOut]
    /// The loads whose layouts still run off the render thread.
    let textLoadsInFlight: Int
    /// The changes of the text boxes, in order. The list goes back to the inbox (PERF-01).
    var textEdits: [TextEdit]
    /// The cards of a load with their title layouts (D-92).
    let laidOutCards: [CardStore.LaidOut]
    /// The number of cards that a card load reserves room for, or `nil`.
    let cardReserve: Int?
    /// The loads whose title layouts still run off the render thread.
    let cardLoadsInFlight: Int
    /// The changes of the cards, in order. The list goes back to the inbox (PERF-01).
    var cardEdits: [CardEdit]
    /// The previews that the loader decoded (D-97).
    let decodedPreviews: [DecodedPreview]
    /// A request of a preview of this canvas, or `nil` (D-97).
    let previewRender: PreviewRenderRequest?
    /// An open or a leave that starts, or `nil` (D-98).
    let transitionStart: TransitionStart?
    /// The new weight of the parent image, or `nil`.
    let transitionWeight: Double?
    /// `true` if the transition ends.
    let endsTransition: Bool
    /// The new state of a pinch-out exit, or `nil` (CARD-05).
    let pinchExit: PinchExit?
    /// `true` if the pinch-out exit ends.
    let endsPinchExit: Bool
    /// A flight of the camera that starts, or `nil` (D-121).
    let flight: RenderFlight?
    /// `true` if a camera from the main thread ends the flight (D-121).
    let endsFlight: Bool
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
            || !laidOutText.isEmpty || !textEdits.isEmpty
            || !laidOutCards.isEmpty || !cardEdits.isEmpty || !decodedPreviews.isEmpty
            || previewRender != nil || transitionStart != nil || transitionWeight != nil
            || endsTransition || pinchExit != nil || endsPinchExit || flight != nil
            || endsFlight || eraserStart != nil
            || !eraserSamples.isEmpty || endsEraser
            || eraserReady != nil
    }
}

/// The emptied lists of a frame, which go back to the inbox for reuse (PERF-01).
struct SpareLists {
    var eraserSamples: [Point] = []
    var textEdits: [TextEdit] = []
    var cardEdits: [CardEdit] = []
}

extension RenderInput {
    /// Moves the lists out of the input and empties them with their capacity. The edit lists go
    /// back too, so a drag step allocates no list (m10-plan.md task 3.1).
    mutating func emptyLists() -> SpareLists {
        var spares = SpareLists()
        swap(&spares.eraserSamples, &eraserSamples)
        swap(&spares.textEdits, &textEdits)
        swap(&spares.cardEdits, &cardEdits)
        spares.eraserSamples.removeAll(keepingCapacity: true)
        spares.textEdits.removeAll(keepingCapacity: true)
        spares.cardEdits.removeAll(keepingCapacity: true)
        return spares
    }
}

extension RenderInbox {
    /// Keeps each spare list that holds more room than the list that the inbox keeps.
    mutating func keep(_ spares: SpareLists) {
        let samples = spares.eraserSamples
        if spareEraserSamples.capacity < samples.capacity { spareEraserSamples = samples }
        if spareTextEdits.capacity < spares.textEdits.capacity { spareTextEdits = spares.textEdits }
        if spareCardEdits.capacity < spares.cardEdits.capacity { spareCardEdits = spares.cardEdits }
    }
}
