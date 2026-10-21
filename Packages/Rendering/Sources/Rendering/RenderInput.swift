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
    /// The changes of the text boxes, in order.
    let textEdits: [TextEdit]
    /// The cards of a load with their title layouts (D-92).
    let laidOutCards: [CardStore.LaidOut]
    /// The number of cards that a card load reserves room for, or `nil`.
    let cardReserve: Int?
    /// The loads whose title layouts still run off the render thread.
    let cardLoadsInFlight: Int
    /// The changes of the cards, in order.
    let cardEdits: [CardEdit]
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
            || endsTransition || pinchExit != nil || endsPinchExit || eraserStart != nil
            || !eraserSamples.isEmpty || endsEraser
            || eraserReady != nil
    }
}
