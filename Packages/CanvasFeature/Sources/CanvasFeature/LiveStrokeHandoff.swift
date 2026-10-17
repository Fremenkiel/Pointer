import Geometry
import Model
import PencilKit
import Rendering
import os

/// Moves each finished stroke from the live `PKCanvasView` to the Metal renderer
/// (architecture.md 4.2).
///
/// The renderer draws the stroke and calls back after the frame is on the screen. Then the
/// handoff removes only that stroke from the `PKDrawing`. Thus no frame shows the stroke twice
/// or not at all. While the pencil draws the next stroke, the removal waits, so that a change of
/// the drawing does not cancel the live stroke.
@MainActor
final class LiveStrokeHandoff {
    private let canvasView: PKCanvasView
    private let renderer: CanvasRenderer
    private var converter: PencilKitStrokeConverter
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Canvas")
    /// Strokes of the drawing that went to the renderer.
    private var handedOff: Set<StrokeKey> = []
    /// Strokes that the screen shows in Metal, so the drawing can drop them.
    private var presented: Set<StrokeKey> = []
    private var isChangingDrawing = false

    /// `true` while the pencil draws a live stroke.
    var isToolInUse = false {
        didSet { if !isToolInUse { removePresentedStrokes() } }
    }

    /// Called with the new model strokes of each handoff.
    var onStrokes: (([Stroke]) -> Void)?

    /// Returns the number of strokes that the canvas can still take (`Limits.maxStrokesPerCanvas`).
    var remainingCapacity: () -> Int = { Limits.maxStrokesPerCanvas }

    /// Makes the handoff for a canvas view.
    init(canvasView: PKCanvasView, renderer: CanvasRenderer, converter: PencilKitStrokeConverter) {
        self.canvasView = canvasView
        self.renderer = renderer
        self.converter = converter
    }

    /// The number of strokes in the live drawing.
    var liveStrokeCount: Int { canvasView.drawing.strokes.count }

    /// Hands off each new stroke of the drawing. The canvas calls it when the drawing changes.
    ///
    /// - Precondition: The view size is positive.
    func drawingDidChange(camera: Camera, viewSize: Size) {
        precondition(viewSize.width > 0 && viewSize.height > 0, "The canvas view has no size")
        guard !isChangingDrawing else { return }
        for stroke in canvasView.drawing.strokes {
            let key = StrokeKey(stroke)
            guard !handedOff.contains(key) else { continue }
            handedOff.insert(key)
            handOff(stroke, key: key, camera: camera, viewSize: viewSize)
        }
        assert(
            handedOff.count >= canvasView.drawing.strokes.count,
            "Each live stroke is handed off"
        )
    }

    private func handOff(_ stroke: PKStroke, key: StrokeKey, camera: Camera, viewSize: Size) {
        do {
            let strokes = try converter.convert(stroke, camera: camera, viewSize: viewSize)
            guard strokes.count <= remainingCapacity() else {
                // The short limit message of architecture.md section 10 comes with M10.
                logger.error("The canvas is at its stroke limit. A live stroke is refused.")
                presented.insert(key)
                removePresentedStrokes()
                return
            }
            renderer.add(strokes) { [weak self] in
                self?.presented.insert(key)
                self?.removePresentedStrokes()
            }
            onStrokes?(strokes)
        } catch {
            logger.error("A live stroke could not be converted: \(String(describing: error))")
            presented.insert(key)
            removePresentedStrokes()
        }
    }

    private func removePresentedStrokes() {
        guard !isToolInUse, !presented.isEmpty else { return }
        let drawing = canvasView.drawing
        let remaining = drawing.strokes.filter { !presented.contains(StrokeKey($0)) }
        handedOff.subtract(presented)
        presented.removeAll()
        guard remaining.count != drawing.strokes.count else { return }
        isChangingDrawing = true
        canvasView.drawing = PKDrawing(strokes: remaining)
        isChangingDrawing = false
        assert(
            canvasView.drawing.strokes.count == remaining.count,
            "The drawing kept removed strokes"
        )
    }
}
