import DesignSystem
import PencilKit
import Rendering
import UIKit

/// The canvas view: the Metal view with one `PKCanvasView` on top for the live stroke
/// (architecture.md 4.1).
@MainActor
final class CanvasView: UIView {
    /// The Metal view with all finished ink.
    let inkView: InkView
    /// The live `PKCanvasView`. It never zooms or scrolls, and never becomes the first responder.
    let liveCanvas = LiveCanvasView()
    /// The hover dot of the pencil, above the live canvas (D-126).
    let hoverDot = HoverDotLayer()
    /// Runs at the hit test of each new touch, before a gesture recognizer gets the touch.
    var onTouchHitTest: (() -> Void)?

    /// Makes the view.
    init(renderer: CanvasRenderer) {
        inkView = InkView(renderer: renderer)
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.canvasBackground
        isMultipleTouchEnabled = true
        configureLiveCanvas()
        addSubview(inkView)
        addSubview(liveCanvas)
        layer.addSublayer(hoverDot.layer)
        assert(liveCanvas.superview === self, "The live canvas lies on top of the ink")
    }

    /// Returns `true` for the views of the canvas surface: this view, the ink view, and the
    /// live canvas with its subviews. A view on top, as a button, is not part of it (F-06).
    func isSurface(_ view: UIView) -> Bool {
        view === self || view === inkView || view.isDescendant(of: liveCanvas)
    }

    /// Tells the canvas about a new touch before PencilKit sees it, so that the pen width of a
    /// pinch that still runs is in place for the stroke (D-131). UIKit hit-tests a touch once,
    /// when it begins, so this runs once per touch and not at each sample.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if event?.type == .touches { onTouchHitTest?() }
        return super.hitTest(point, with: event)
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
        hoverDot.layer.contentsScale = traitCollection.displayScale
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
        liveCanvas.tool = PenTool.inkingTool(width: .standard, zoom: 1)
    }
}
