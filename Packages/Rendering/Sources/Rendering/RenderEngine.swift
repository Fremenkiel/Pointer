import Dispatch
import Geometry
import Metal
import Model
import QuartzCore
import Synchronization

/// The renderer state that the main actor and the render thread share (D-42).
///
/// The frame work sits behind one lock and the inbox behind another. The main actor writes only
/// the inbox, so it never waits for a frame. The render thread takes the inbox at the start of
/// each frame.
final class RenderEngine: Sendable {
    /// The longest wait of a frame for the camera of its display frame, in seconds. The display
    /// link and the main thread wake on the same display frame. Without the wait, about 1 frame
    /// in 10 of a pan found no new camera and drew nothing (frame-loop test, 2026-10-17). The
    /// frame latency of 2 frames leaves time for the wait.
    static let cameraWaitBudget = 0.003

    /// The GPU of the renderer.
    let device: any MTLDevice
    private let core: Mutex<FrameRenderer>
    private let inbox = Mutex(RenderInbox())
    private let cameraArrived = DispatchSemaphore(value: 0)

    /// Makes the engine on the system GPU.
    ///
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    init(
        configuration: RendererConfiguration,
        onCompleted: @escaping @Sendable (UInt64, Double) -> Void = { _, _ in },
        onPresented: @escaping @Sendable (UInt64) -> Void
    ) throws(RenderingError) {
        let renderer = try FrameRenderer(
            configuration: configuration,
            onCompleted: onCompleted,
            onPresented: onPresented
        )
        device = renderer.resources.device
        core = Mutex(renderer)
        assert(
            core.withLock { $0.resources.device === device },
            "The engine uses the GPU of its frames"
        )
    }

    /// `true` if a change waits or the renderer had work after its last frame. A camera change
    /// alone does not count, because it wakes the frame loop by itself.
    var needsMoreFrames: Bool { inbox.withLock { $0.hasContentChange || $0.rendererHasWork } }

    /// The number of strokes in the renderer after its last frame.
    var strokeCount: Int { inbox.withLock { $0.strokeCount } }

    /// Applies a change to the inbox and wakes the frame loop if it sleeps.
    func post(_ change: (inout RenderInbox) -> Void) {
        let (wake, signalsCamera) = inbox.withLock { box -> ((@Sendable () -> Void)?, Bool) in
            change(&box)
            let signalsCamera = box.isWaitingForCamera && box.hasNewCamera
            if signalsCamera { box.isWaitingForCamera = false }
            assert(!box.isWaitingForCamera || !box.hasNewCamera, "A waiting frame misses a camera")
            guard box.isSleeping, let wake = box.wake else { return (nil, signalsCamera) }
            box.isSleeping = false
            return (wake, signalsCamera)
        }
        if signalsCamera { cameraArrived.signal() }
        wake?()
    }

    /// Waits up to `cameraWaitBudget` for a new camera if the camera moved in the last frame.
    private func waitForCameraIfMoving() {
        let waits = inbox.withLock { box in
            assert(!box.isWaitingForCamera, "Two frames wait for the camera at once")
            guard box.cameraMovedInLastFrame, !box.hasNewCamera else { return false }
            box.isWaitingForCamera = true
            return true
        }
        guard waits else { return }
        let result = cameraArrived.wait(timeout: .now() + Self.cameraWaitBudget)
        let isLateSignal = inbox.withLock { box in
            let wasWaiting = box.isWaitingForCamera
            box.isWaitingForCamera = false
            return result == .timedOut && !wasWaiting
        }
        // A camera that came after the timeout but before the reset signaled once. Take that
        // signal now, so the next wait does not end at once.
        if isLateSignal { _ = cameraArrived.wait(timeout: .now()) }
    }

    /// Puts the frame loop to sleep if no change waits.
    ///
    /// - Returns: `true` if the loop sleeps now. The next change calls the wake function.
    func sleepIfIdle() -> Bool {
        inbox.withLock { box in
            assert(!box.isSleeping, "A sleeping frame loop drew a frame")
            guard !box.hasContentChange, !box.hasNewCamera, !box.rendererHasWork else {
                return false
            }
            box.isSleeping = true
            return true
        }
    }

    /// Takes the waiting changes and draws one frame on the calling thread.
    ///
    /// - Precondition: `drawableSize` is finite.
    /// - Returns: Whether the frame drew, and whether the renderer needs another frame.
    func renderFrame(
        drawableSize: CGSize,
        deadline: TimeInterval?,
        drawable: DrawableSource
    ) -> FrameOutcome {
        precondition(drawableSize.width.isFinite && drawableSize.height.isFinite, "Size not finite")
        waitForCameraIfMoving()
        var input = inbox.withLock { $0.take() }
        let result = core.withLock { renderer -> FrameResult in
            Self.draw(
                input,
                with: renderer,
                drawableSize: drawableSize,
                deadline: deadline,
                drawable: drawable
            )
        }
        assert(result.didDraw || !result.needsMore, "A frame without work asks for more frames")
        // The sample list goes back to the inbox, so the next frame allocates no list (PERF-01).
        var samples: [Point] = []
        swap(&samples, &input.eraserSamples)
        samples.removeAll(keepingCapacity: true)
        inbox.withLock { box in
            box.strokeCount = result.count
            box.rendererHasWork = result.needsMore
            if box.spareEraserSamples.capacity < samples.capacity {
                box.spareEraserSamples = samples
            }
        }
        if let record = result.record { input.observer?.didRender(record) }
        return FrameOutcome(didDraw: result.didDraw, needsMore: result.needsMore)
    }

    /// Applies the input and draws a frame if the input or the renderer has work.
    private static func draw(
        _ input: RenderInput,
        with renderer: FrameRenderer,
        drawableSize: CGSize,
        deadline: TimeInterval?,
        drawable: DrawableSource
    ) -> FrameResult {
        let start = CACurrentMediaTime()
        apply(input, to: renderer)
        var needsMore = false
        var record: FrameRecord?
        if !input.hasChange && !renderer.needsMoreFrames {
            return FrameResult(didDraw: false, needsMore: false, count: renderer.store.count)
        } else if let observer = input.observer {
            // The closure goes straight to `measure`, so it does not escape and allocates no box
            // for `needsMore` (PERF-01).
            observer.measure {
                needsMore = renderer.renderFrame(
                    drawableSize: drawableSize,
                    deadline: deadline,
                    drawable: drawable
                )
            }
            record = Self.record(of: renderer, start: start, target: deadline ?? start)
        } else {
            needsMore = renderer.renderFrame(
                drawableSize: drawableSize,
                deadline: deadline,
                drawable: drawable
            )
        }
        assert(renderer.store.count <= Limits.maxStrokesAfterErase, "The renderer passed its bound")
        return FrameResult(
            didDraw: true,
            needsMore: needsMore,
            count: renderer.store.count,
            record: record
        )
    }

    /// Runs `body` with the frame work on the calling thread, for work outside the frame loop.
    func withRenderer<Result: Sendable, Failure: Error>(
        _ body: (inout sending FrameRenderer) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try core.withLock { renderer throws(Failure) -> Result in try body(&renderer) }
    }

    private static func apply(_ input: RenderInput, to renderer: FrameRenderer) {
        assert(input.edits.isEmpty || input.editHandoff > 0, "Edits need a handoff number")
        if let viewport = input.viewport {
            renderer.setViewport(viewSize: viewport.size, displayScale: viewport.scale)
        }
        if let camera = input.camera {
            renderer.camera = camera
        }
        if !input.loaded.isEmpty {
            renderer.load(input.loaded)
        }
        if let ready = input.eraserReady {
            renderer.isEraserReady = ready
        }
        renderer.applyEraser(
            start: input.eraserStart,
            samples: input.eraserSamples,
            ends: input.endsEraser
        )
        for edit in input.edits {
            renderer.apply(edit)
        }
        if !input.edits.isEmpty {
            renderer.markHandoff(input.editHandoff, wantsCompletion: input.editsWantCompletion)
        }
        if let observer = input.observer {
            renderer.onCommit = { observer.willCommit($0, drawable: $1) }
        } else if renderer.onCommit != nil {
            renderer.onCommit = nil
        }
    }

    private static func record(
        of renderer: FrameRenderer,
        start: Double,
        target: Double
    ) -> FrameRecord {
        let front = renderer.layer?.front
        let milliseconds = (CACurrentMediaTime() - start) * 1000
        assert(milliseconds >= 0, "The frame time \(milliseconds) ms is negative")
        return FrameRecord(
            targetTime: target,
            cpuMilliseconds: milliseconds,
            front: front.map { ObjectIdentifier($0.texture) },
            frontRect: front?.canvasRect,
            camera: renderer.camera
        )
    }
}

/// The values that one frame gives back from inside the lock.
private struct FrameResult: Sendable {
    let didDraw: Bool
    let needsMore: Bool
    let count: Int
    var record: FrameRecord?
}
