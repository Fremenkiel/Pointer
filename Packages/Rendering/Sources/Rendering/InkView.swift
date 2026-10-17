import Geometry
import QuartzCore
import UIKit

/// A view with a `CAMetalLayer` that the renderer draws in a `UIUpdateLink` frame loop
/// (architecture.md 5.1).
///
/// The link runs only while the renderer has work: a camera change, a build, or a stroke that
/// waits for the handoff.
@MainActor
public final class InkView: UIView {
    /// The renderer of the canvas.
    public let renderer: CanvasRenderer
    private var updateLink: UIUpdateLink?
    /// `true` after `requestFrame()` until the next frame draws.
    private var isFrameRequested = false
    /// The frames in a row without work.
    private var idleFrames = 0
    /// The link keeps its continuous updates for this many frames without work, about 0.1 s at
    /// 120 Hz. Without the pause, the link turned off between the frames of a pan, and the
    /// display fell back to 60 Hz on the device.
    static let idleFramesBeforeSleep = 12

    /// Called at the start of each frame with the model time of the frame, before the renderer
    /// draws. It returns `true` while it needs more frames, for example during a camera animation.
    public var onFrame: ((TimeInterval) -> Bool)?

    /// The frame rate range of architecture.md 5.1.
    static let frameRates = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)

    /// The layer class: Metal.
    override public static var layerClass: AnyClass { CAMetalLayer.self }

    /// Makes the view and sets up its layer for the renderer.
    public init(renderer: CanvasRenderer) {
        self.renderer = renderer
        super.init(frame: .zero)
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
        renderer.configure(metalLayer)
        renderer.onNeedsFrame = { [weak self] in self?.requestFrame() }
        assert(metalLayer.pixelFormat == .bgra8Unorm, "The renderer did not set up the layer")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // swiftlint:disable:next safe_07_fatal_error
        fatalError("InkView has no coder support")
    }

    private var metalLayer: CAMetalLayer {
        guard let metalLayer = layer as? CAMetalLayer else {
            preconditionFailure("The layer class of InkView is CAMetalLayer")
        }
        return metalLayer
    }

    /// Starts the frame loop when the view joins a window and stops it when the view leaves.
    override public func didMoveToWindow() {
        super.didMoveToWindow()
        updateLink?.isEnabled = false
        updateLink = window == nil ? nil : makeUpdateLink()
    }

    /// Updates the drawable size and the viewport of the renderer.
    override public func layoutSubviews() {
        super.layoutSubviews()
        let scale = traitCollection.displayScale
        guard scale > 0, bounds.width > 0, bounds.height > 0 else { return }
        let viewSize = Size(width: bounds.width, height: bounds.height)
        assert(viewSize.width.isFinite && viewSize.height.isFinite, "View bounds are not finite")
        assert(scale.isFinite, "Display scale is not finite")
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: viewSize.width * scale,
            height: viewSize.height * scale
        )
        renderer.setViewport(viewSize: viewSize, displayScale: scale)
        requestFrame()
    }

    /// Asks the frame loop for frames until the renderer has no work.
    public func requestFrame() {
        isFrameRequested = true
        updateLink?.requiresContinuousUpdates = true
    }

    private func makeUpdateLink() -> UIUpdateLink {
        precondition(window != nil, "The frame loop needs a window")
        let link = UIUpdateLink(view: self)
        link.addAction(to: .afterCADisplayLinkDispatch) { [weak self] _, info in
            self?.drawFrame(info)
        }
        // The low-latency settings of architecture.md 5.1 serve the eraser path, which comes with
        // M4. Without an eraser they only halve the time of each frame: the device test of
        // 2026-10-17 showed a late frame on every second frame of a pan with them on.
        link.wantsLowLatencyEventDispatch = false
        link.wantsImmediatePresentation = false
        link.preferredFrameRateRange = Self.frameRates
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        assert(link.isEnabled, "The frame loop did not start")
        return link
    }

    /// Returns `true` if the next frame has work: a request, an animation, or renderer work.
    func shouldDrawFrame(isAnimating: Bool) -> Bool {
        isFrameRequested || isAnimating || renderer.needsMoreFrames
    }

    /// The link also calls this on UI updates that other views cause, for example the hover
    /// preview of PencilKit on each display frame. A frame without work draws nothing, because
    /// an extra Metal frame on each of these updates starves the drawables of both renderers.
    private func drawFrame(_ info: UIUpdateInfo) {
        let isAnimating = onFrame?(info.modelTime) ?? false
        guard shouldDrawFrame(isAnimating: isAnimating) else {
            idleFrames += 1
            if idleFrames > Self.idleFramesBeforeSleep {
                updateLink?.requiresContinuousUpdates = false
            }
            return
        }
        idleFrames = 0
        isFrameRequested = false
        renderer.renderFrame(into: metalLayer, deadline: info.completionDeadlineTime)
        updateLink?.requiresContinuousUpdates = true
    }
}
