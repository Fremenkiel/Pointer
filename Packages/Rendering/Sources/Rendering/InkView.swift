import Geometry
import QuartzCore
import UIKit

/// A view with a `CAMetalLayer` that the renderer draws on its render thread (architecture.md
/// 5.1, D-42).
///
/// The render thread starts when the view joins a window and stops when it leaves. A
/// `UIUpdateLink` on the main thread steps the camera animations. It runs only while an
/// animation runs.
@MainActor
public final class InkView: UIView {
    /// The renderer of the canvas.
    public let renderer: CanvasRenderer
    private var renderThread: RenderThread?
    private var updateLink: UIUpdateLink?
    /// `true` after `requestFrame()` until the next step.
    private var isFrameRequested = false
    /// The steps in a row without an animation.
    private var idleSteps = 0
    /// The link keeps its continuous updates for this many steps without an animation, about
    /// 0.1 s at 120 Hz, so that a new animation starts on the next display frame.
    static let idleStepsBeforeSleep = 12

    /// Called at each display frame with the model time of the frame. It returns `true` while it
    /// needs more frames, for example during a camera animation.
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

    /// Starts the render thread and the step link when the view joins a window, and stops both
    /// when the view leaves.
    override public func didMoveToWindow() {
        super.didMoveToWindow()
        renderThread?.stop()
        renderThread = nil
        updateLink?.isEnabled = false
        updateLink = nil
        guard window != nil else { return }
        let thread = RenderThread(
            engine: renderer.engine,
            layer: metalLayer,
            frameRates: Self.frameRates
        )
        thread.start()
        renderThread = thread
        updateLink = makeUpdateLink()
        assert(updateLink?.isEnabled == true, "The step link runs while the view has a window")
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
        let drawableSize = CGSize(width: viewSize.width * scale, height: viewSize.height * scale)
        if let renderThread {
            renderThread.setDrawableSize(drawableSize)
        } else {
            metalLayer.drawableSize = drawableSize
        }
        renderer.setViewport(viewSize: viewSize, displayScale: scale)
    }

    /// Asks the step link for display frames until no animation runs.
    public func requestFrame() {
        isFrameRequested = true
        updateLink?.requiresContinuousUpdates = true
    }

    private func makeUpdateLink() -> UIUpdateLink {
        precondition(window != nil, "The step link needs a window")
        let link = UIUpdateLink(view: self)
        link.addAction(to: .afterCADisplayLinkDispatch) { [weak self] _, info in
            self?.step(info)
        }
        link.preferredFrameRateRange = Self.frameRates
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        assert(link.isEnabled, "The step link did not start")
        return link
    }

    /// Returns `true` if the next display frame needs a step: a request or an animation.
    func needsStep(isAnimating: Bool) -> Bool {
        isFrameRequested || isAnimating
    }

    private func step(_ info: UIUpdateInfo) {
        assert(updateLink != nil, "A step runs only with a step link")
        let isAnimating = onFrame?(info.modelTime) ?? false
        guard needsStep(isAnimating: isAnimating) else {
            idleSteps += 1
            if idleSteps > Self.idleStepsBeforeSleep {
                updateLink?.requiresContinuousUpdates = false
            }
            return
        }
        idleSteps = 0
        isFrameRequested = false
        updateLink?.requiresContinuousUpdates = true
    }
}
