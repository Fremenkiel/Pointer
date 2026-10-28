import Foundation
import QuartzCore
import os

/// The thread that encodes the frames of one `InkView` (D-42).
///
/// A `CAMetalDisplayLink` on the run loop of the thread gives each frame its drawable, so
/// `nextDrawable()` never blocks the main thread. The link pauses when the renderer has no work,
/// and the next change in the inbox wakes it.
///
/// Safe as `@unchecked Sendable`: `layer`, `link`, and `idleFrames` are used only on the render
/// thread after `start()`. `runLoop` is written once on the render thread before `start()`
/// returns, and the semaphore orders that write before every read. `CFRunLoopPerformBlock` and
/// `CFRunLoopWakeUp` are safe to call from any thread.
final class RenderThread: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    /// The link keeps running for this many frames without work, about 0.1 s at 120 Hz. Without
    /// the pause, the link turned off between the frames of a pan, and the display fell back to
    /// 60 Hz on the device (M2).
    static let idleFramesBeforeSleep = 12
    /// The frames between the start of a frame and its presentation. The display link gives each
    /// update this much time ahead of the presentation.
    static let frameLatency: Float = 2
    /// The name of the thread, for traces and checks.
    static let threadName = "Pointer render"

    private let engine: RenderEngine
    private let layer: CAMetalLayer
    private let frameRates: CAFrameRateRange
    private let ready = DispatchSemaphore(value: 0)
    private var link: CAMetalDisplayLink?
    private var runLoop: CFRunLoop?
    private var idleFrames = 0
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Rendering")

    /// Makes a render thread for a layer. It starts with `start()`.
    init(engine: RenderEngine, layer: CAMetalLayer, frameRates: CAFrameRateRange) {
        self.engine = engine
        self.layer = layer
        self.frameRates = frameRates
        super.init()
    }

    /// Starts the thread and its display link, and waits until the run loop exists.
    ///
    /// - Precondition: The thread did not start before.
    func start() {
        precondition(runLoop == nil, "The render thread already runs")
        let thread = Thread { [self] in run() }
        thread.name = Self.threadName
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        assert(runLoop != nil, "The render thread has a run loop")
        engine.post { [self] box in
            box.wake = { [weak self] in self?.wake() }
            box.isSleeping = false
        }
    }

    /// Stops the display link and the thread. The thread ends after its current frame.
    func stop() {
        precondition(runLoop != nil, "The render thread did not start")
        engine.post { box in
            box.wake = nil
            box.isSleeping = false
        }
        perform { [self] in
            assert(Thread.current.name == Self.threadName, "The stop runs on the render thread")
            link?.invalidate()
            link = nil
            // No frame runs after the link stops, so a preview render that did not end gets
            // `nil`, and the leave that waits for it ends (D-131).
            engine.endPreviewRender()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
    }

    /// Resumes the display link after a sleep. Any thread can call it.
    func wake() {
        // A wake can come after the stop, and a run loop that ended keeps its blocks. A strong
        // capture there kept the thread and its engine for the rest of the run.
        perform { [weak self] in self?.link?.isPaused = false }
    }

    /// Sets the drawable size on the render thread, so it never changes during a frame. The
    /// block captures the thread weakly, as `wake()` does (D-194).
    func setDrawableSize(_ size: CGSize) {
        precondition(size.width.isFinite && size.height.isFinite, "Drawable size is not finite")
        precondition(size.width >= 0 && size.height >= 0, "Drawable size \(size) is negative")
        perform { [weak self] in
            guard let self else { return }
            layer.drawableSize = size
            link?.isPaused = false
        }
    }

    /// Draws one frame with the drawable of the update.
    func metalDisplayLink(
        _ link: CAMetalDisplayLink,
        needsUpdate update: CAMetalDisplayLink.Update
    ) {
        assert(link === self.link, "A stopped display link asks for a frame")
        let drawable = update.drawable
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let outcome = engine.renderFrame(
            drawableSize: size,
            deadline: update.targetTimestamp,
            drawable: .drawable(drawable)
        )
        // A frame that drew is not idle, even if it needs no next frame: during a pan of little
        // content, each frame completes its build, and a pause there cost frames on the device.
        guard !outcome.didDraw, !outcome.needsMore else {
            idleFrames = 0
            return
        }
        idleFrames += 1
        assert(idleFrames <= Self.idleFramesBeforeSleep + 1, "The link missed its sleep")
        guard idleFrames > Self.idleFramesBeforeSleep else { return }
        guard engine.sleepIfIdle() else {
            // A change arrived. If its frame draws nothing, the link tries again after it
            // (review of 2026-10-28).
            idleFrames = Self.idleFramesBeforeSleep
            return
        }
        idleFrames = 0
        link.isPaused = true
    }

    private func run() {
        precondition(link == nil, "The render thread runs once")
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        link.preferredFrameRateRange = frameRates
        link.preferredFrameLatency = Self.frameLatency
        link.add(to: .current, forMode: .default)
        assert(link.delegate === self, "The display link reports to this thread")
        self.link = link
        runLoop = CFRunLoopGetCurrent()
        ready.signal()
        // The run loop runs until `stop()` calls `CFRunLoopStop`. It has no loop in Swift code.
        CFRunLoopRun()
        logger.debug("The render thread ended")
    }

    private func perform(_ block: @escaping @Sendable () -> Void) {
        guard let runLoop else {
            preconditionFailure("The render thread did not start")
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}
