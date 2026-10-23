import UIKit

/// The hover dot of the pencil (architecture.md 4.6, PEN-04, D-126, D-128).
extension CanvasViewController {
    /// Adds the hover recognizer of the pencil to the canvas view.
    func installHover() {
        let recognizer = PencilHoverRecognizer(target: self, action: #selector(handleHover(_:)))
        canvasView.addGestureRecognizer(recognizer)
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        let location = recognizer.location(in: canvasView)
        switch recognizer.state {
        case .began:
            hoverBegan(at: location, isPreviewOn: UIPencilInteraction.prefersHoverToolPreview)
        case .changed:
            hoverMoved(to: location)
        default:
            hideHoverDot()
        }
    }

    /// Starts a hover at `location`. `isPreviewOn` is the setting "Show Hover Preview", which
    /// the user can change in Settings while the app runs (D-128).
    func hoverBegan(at location: CGPoint, isPreviewOn: Bool) {
        canvasView.hoverDot.isPreviewOn = isPreviewOn
        hoverMoved(to: location)
    }

    /// Moves the dot to a hover sample, or hides it (D-128). It allocates nothing in Pointer code
    /// (PERF-01), and the interval "Hover" times it (PERF-03).
    func hoverMoved(to location: CGPoint) {
        CanvasSignpost.begin("Hover")
        let mark = HoverDot.mark(
            tool: tool,
            isPreviewOn: canvasView.hoverDot.isPreviewOn,
            location: location,
            isPencilDown: toolState.isPencilDown,
            isInFlight: !takesPencilActions
        )
        canvasView.hoverDot.show(mark)
        CanvasSignpost.end("Hover")
    }

    /// Hides the dot: at the end of a hover, at a pencil down, and at the start of a card flight.
    func hideHoverDot() {
        canvasView.hoverDot.show(nil)
    }

    /// Shows the shape of a new tool at once while the dot shows.
    func toolDidChangeForHover() {
        guard let center = canvasView.hoverDot.shownCenter else { return }
        hoverMoved(to: center)
    }
}
