import PencilKit
import Rendering
import UIKit

/// The canvas view: the Metal view with one `PKCanvasView` on top for the live stroke
/// (architecture.md 4.1).
@MainActor
final class CanvasView: UIView {
    /// The Metal view with all finished ink.
    let inkView: InkView
    /// The live `PKCanvasView`. It never zooms or scrolls.
    let liveCanvas = PKCanvasView()

    /// Makes the view.
    init(renderer: CanvasRenderer) {
        inkView = InkView(renderer: renderer)
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        configureLiveCanvas()
        addSubview(inkView)
        addSubview(liveCanvas)
        assert(liveCanvas.superview === self, "The live canvas lies on top of the ink")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // swiftlint:disable:next safe_07_fatal_error
        fatalError("CanvasView has no coder support")
    }

    /// Both views fill the canvas view. The live canvas stays at zoom 1 with no scroll.
    override func layoutSubviews() {
        super.layoutSubviews()
        inkView.frame = bounds
        liveCanvas.frame = bounds
        liveCanvas.contentSize = bounds.size
        liveCanvas.contentOffset = .zero
    }

    private func configureLiveCanvas() {
        liveCanvas.backgroundColor = .clear
        liveCanvas.isOpaque = false
        liveCanvas.drawingPolicy = .pencilOnly
        liveCanvas.overrideUserInterfaceStyle = .light
        liveCanvas.minimumZoomScale = 1
        liveCanvas.maximumZoomScale = 1
        liveCanvas.isScrollEnabled = false
        liveCanvas.contentInsetAdjustmentBehavior = .never
        liveCanvas.isMultipleTouchEnabled = true
        liveCanvas.tool = PenTool.inkingTool(zoom: 1)
    }
}
