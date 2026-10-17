import Metal
import QuartzCore
import UIKit

/// The settings that the control bar changes.
struct SpikeSettings {
    var presentsWithTransaction = true
    var lowLatency = true
    var filterEnabled = true
    var minCutoff = 1.0
    var beta = 0.007
    var derivativeCutoff = 1.0
    var zoom = 1.0
    /// Test value only. The product documents do not fix the pen width.
    var penWidth = 2.0
}

/// A `CAMetalLayer` view that draws capsules in a `UIUpdateLink` loop (architecture.md 5.1).
class MetalCanvasView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    let renderer = CapsuleRenderer()
    let log = LatencyLog()
    var settings = SpikeSettings() { didSet { applySettings() } }

    /// The temporary part of the live stroke, redrawn each frame.
    var tail: [Capsule] = []
    /// True while something waits for the next frame.
    var needsRender = false

    /// Called on the main thread after a frame is on the glass, with the presented time.
    var onPresented: ((Double) -> Void)?

    /// Set by subclasses for the next frame: the newest real sample and the first handler time.
    var pendingSampleTime: Double?
    var pendingEventTime: Double?

    private var updateLink: UIUpdateLink?
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        isMultipleTouchEnabled = true
        metalLayer.device = renderer.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.maximumDrawableCount = 2
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        applySettings()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, updateLink == nil else { return }
        let link = UIUpdateLink(view: self)
        link.addAction(to: .afterEventDispatch) { [weak self] _, info in
            if !info.isPerformingLowLatencyPhases { self?.render(info) }
        }
        link.addAction(to: .afterLowLatencyEventDispatch) { [weak self] _, info in
            self?.render(info)
        }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.requiresContinuousUpdates = false
        link.isEnabled = true
        updateLink = link
        applySettings()
        requestFrame()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? traitCollection.displayScale
        contentScaleFactor = scale
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        requestFrame()
    }

    /// Keeps the update link running until the next frame is drawn.
    func requestFrame() {
        needsRender = true
        updateLink?.requiresContinuousUpdates = true
    }

    /// Ends continuous updates. Call at pencil lift after the last frame.
    func allowIdle() {
        if !needsRender { updateLink?.requiresContinuousUpdates = false }
    }

    var keepsRunning = false

    func clear() {
        renderer.clear()
        tail = []
        requestFrame()
    }

    private func applySettings() {
        metalLayer.presentsWithTransaction = settings.presentsWithTransaction
        updateLink?.wantsLowLatencyEventDispatch = settings.lowLatency
        updateLink?.wantsImmediatePresentation = settings.lowLatency
    }

    private func render(_ info: UIUpdateInfo) {
        log.linkCalls += 1
        guard needsRender else {
            if !keepsRunning { updateLink?.requiresContinuousUpdates = false }
            return
        }
        let renderStart = CACurrentMediaTime()
        guard let drawable = metalLayer.nextDrawable() else {
            log.droppedDrawables += 1
            return
        }
        let acquired = CACurrentMediaTime()
        needsRender = false
        log.framesDrawn += 1
        guard let commandBuffer = renderer.queue.makeCommandBuffer() else { return }
        renderer.encode(
            into: commandBuffer, texture: drawable.texture, tail: tail,
            zoom: settings.zoom, viewSize: bounds.size, scale: contentScaleFactor)
        let encodeEnd = CACurrentMediaTime()

        var record: FrameRecord?
        if let sample = pendingSampleTime, let event = pendingEventTime {
            record = FrameRecord(
                newestSampleTime: sample, firstEventTime: event, renderStart: renderStart,
                drawableAcquired: acquired, encodeEnd: encodeEnd, submitEnd: 0,
                estimatedPresentationTime: info.estimatedPresentationTime,
                lowLatencyConfirmed: info.isLowLatencyEventDispatchConfirmed,
                immediatePresentationExpected: info.isImmediatePresentationExpected,
                performingLowLatencyPhases: info.isPerformingLowLatencyPhases)
        }
        pendingSampleTime = nil
        pendingEventTime = nil

        let presentedCallback = onPresented
        onPresented = nil
        let box = RecordBox()
        #if targetEnvironment(simulator)
            // The simulator has no presented time. Log the submit time so the screen shows CPU numbers.
            DispatchQueue.main.async { [weak self] in
                if var frame = box.record {
                    frame.presentedTime = frame.submitEnd
                    frame.presentedHandlerTime = frame.submitEnd
                    self?.log.add(frame)
                }
                presentedCallback?(CACurrentMediaTime())
            }
        #else
            drawable.addPresentedHandler { [weak self] presented in
                let handlerTime = CACurrentMediaTime()
                let presentedTime = presented.presentedTime
                DispatchQueue.main.async {
                    if var frame = box.record {
                        frame.presentedTime = presentedTime
                        frame.presentedHandlerTime = handlerTime
                        self?.log.add(frame)
                    }
                    if presentedTime > 0 { presentedCallback?(presentedTime) }
                }
            }
        #endif
        if settings.presentsWithTransaction {
            commandBuffer.commit()
            commandBuffer.waitUntilScheduled()
            drawable.present()
        } else {
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
        record?.submitEnd = CACurrentMediaTime()
        box.record = record
    }
}

/// Carries a frame record into the presented handler.
private final class RecordBox: @unchecked Sendable {
    var record: FrameRecord?
}

/// The `Custom` spike: pencil input with coalesced and predicted touches, the 1€ filter, and capsules.
final class CustomCanvasView: MetalCanvasView {
    private var filter = PointFilter(minCutoff: 1, beta: 0.007, derivativeCutoff: 1)
    private var lastPoint: CGPoint?
    private var activeTouch: UITouch?

    /// The prediction limit of architecture.md 4.2: one frame.
    private let predictionLimit = 0.008

    private func accepts(_ touch: UITouch) -> Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return touch.type == .pencil
        #endif
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        log.touchEvents += 1
        if let first = touches.first { log.lastTouchType = "\(first.type.rawValue)" }
        print("spike: touchesBegan types \(touches.map { $0.type.rawValue }) active \(activeTouch != nil)")
        guard activeTouch == nil, let touch = touches.first(where: accepts) else { return }
        activeTouch = touch
        filter = PointFilter(minCutoff: settings.minCutoff, beta: settings.beta, derivativeCutoff: settings.derivativeCutoff)
        filter.isEnabled = settings.filterEnabled
        lastPoint = nil
        keepsRunning = true
        handle(touch, event: event, isEnd: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        handle(touch, event: event, isEnd: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        handle(touch, event: event, isEnd: true)
        finish()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        finish()
    }

    private func finish() {
        activeTouch = nil
        tail = []
        keepsRunning = false
        requestFrame()
    }

    private func handle(_ touch: UITouch, event: UIEvent?, isEnd: Bool) {
        let now = CACurrentMediaTime()
        log.addTouchClock(ClockPair(eventTime: touch.timestamp, now: now))
        log.acceptedEvents += 1
        let radius = settings.penWidth / 2
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        var capsules: [Capsule] = []
        var newest = touch.timestamp
        for sample in samples {
            let point = filter.filter(canvasPoint(sample.preciseLocation(in: self)), time: sample.timestamp)
            capsules.append(Capsule(lastPoint ?? point, point, radius: radius))
            lastPoint = point
            newest = sample.timestamp
        }
        renderer.append(capsules)

        tail = []
        if !isEnd, var previous = lastPoint {
            var predictionFilter = filter
            for predicted in event?.predictedTouches(for: touch) ?? [] where predicted.timestamp - newest <= predictionLimit {
                let point = predictionFilter.filter(canvasPoint(predicted.preciseLocation(in: self)), time: predicted.timestamp)
                tail.append(Capsule(previous, point, radius: radius))
                previous = point
            }
        }
        pendingSampleTime = newest
        if pendingEventTime == nil { pendingEventTime = now }
        requestFrame()
    }

    private func canvasPoint(_ view: CGPoint) -> CGPoint {
        CGPoint(x: view.x / settings.zoom, y: view.y / settings.zoom)
    }
}
