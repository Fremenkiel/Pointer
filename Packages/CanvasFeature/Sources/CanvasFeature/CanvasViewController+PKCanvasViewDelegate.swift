import PencilKit

/// The events of the live `PKCanvasView`: the handoff of each finished stroke and the state of
/// the tool (architecture.md 4.2).
extension CanvasViewController: PKCanvasViewDelegate {
    /// Hands off each finished stroke.
    public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        handoff.drawingDidChange(
            camera: cameraController.shownCamera,
            viewSize: viewSize,
            penWidth: penSettings.width
        )
        releaseHeldSpring()
    }

    /// The pencil starts a live stroke. The removal of handed-off strokes waits.
    public func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        handoff.isToolInUse = true
    }

    /// The pencil lifted. Handed-off strokes can leave the drawing. The rows of the stroke start
    /// the save when the canvas sends them, so the lift asks for none (review of 2026-10-28).
    public func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        handoff.isToolInUse = false
    }
}
