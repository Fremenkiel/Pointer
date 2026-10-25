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
    /// The frame work behind its lock.
    let core: Mutex<FrameRenderer>
    /// The changes of the main actor behind their lock.
    let inbox = Mutex(RenderInbox())
    private let cameraArrived = DispatchSemaphore(value: 0)
    /// The stored previews of the child canvases, or `nil` without previews (D-97).
    let previewSource: (any PreviewSource)?
    /// The waiting preview requests at most.
    let previewRequestLimit: Int
    /// The loader of the previews, made at the first request.
    let previewLoader = Mutex<PreviewLoader?>(nil)
    /// Runs on the render thread after each frame took the inbox and before it applies the
    /// input. Only the tests set it (D-184).
    private let afterTake: (@Sendable (RenderEngine) -> Void)?
    /// Runs on the posting thread after the inbox lock of a post that gave a waiting frame its
    /// camera. Only the tests set it (D-184).
    private let afterCameraLock: (@Sendable () -> Void)?

    /// Makes the engine on the system GPU.
    ///
    /// - Throws: `RenderingError` if the device has no GPU or a Metal object fails.
    init(
        configuration: RendererConfiguration,
        previewSource: (any PreviewSource)? = nil,
        onCompleted: @escaping @Sendable (UInt64, Double) -> Void = { _, _ in },
        onPresented: @escaping @Sendable (UInt64) -> Void,
        afterTake: (@Sendable (RenderEngine) -> Void)? = nil,
        afterCameraLock: (@Sendable () -> Void)? = nil
    ) throws(RenderingError) {
        let renderer = try FrameRenderer(
            configuration: configuration,
            onCompleted: onCompleted,
            onPresented: onPresented
        )
        device = renderer.resources.device
        core = Mutex(renderer)
        self.previewSource = previewSource
        previewRequestLimit = configuration.previewRequestLimit
        self.afterTake = afterTake
        self.afterCameraLock = afterCameraLock
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

    /// `true` while a text layout of a load runs or waits for a frame (D-92).
    var isLoadingText: Bool { inbox.withLock { $0.isLoadingText } }

    /// `true` while a title layout of a card load runs or waits for a frame (D-92).
    var isLoadingCards: Bool { inbox.withLock { $0.isLoadingCards } }

    /// `true` while text, cards, or previews load, read under one lock, so that no wait on it
    /// ends between the inbox and the frame work (review after M9, section 3.2, item 1).
    var isLoading: Bool {
        inbox.withLock { $0.isLoadingText || $0.isLoadingCards || $0.isLoadingPreviews }
    }

    /// Applies a change to the inbox and wakes the frame loop if it sleeps.
    func post(_ change: (inout RenderInbox) -> Void) {
        let (wake, signalsCamera) = inbox.withLock { box -> ((@Sendable () -> Void)?, Bool) in
            change(&box)
            let signalsCamera = box.isWaitingForCamera && box.hasNewCamera
            // The signal goes inside the lock. After the lock, a wait could time out and reset
            // first, and the late signal would end the next wait at once (review after M8,
            // section 3.2, item 4).
            if signalsCamera {
                box.isWaitingForCamera = false
                cameraArrived.signal()
            }
            guard box.isSleeping, let wake = box.wake else { return (nil, signalsCamera) }
            box.isSleeping = false
            return (wake, signalsCamera)
        }
        if signalsCamera { afterCameraLock?() }
        wake?()
    }

    /// Waits up to `cameraWaitBudget` for a new camera if the camera moved in the last frame.
    func waitForCameraIfMoving() {
        let waits = inbox.withLock { box in
            assert(!box.isWaitingForCamera, "Two frames wait for the camera at once")
            // A flight takes its camera from its closed form, not from the main thread (D-121).
            guard box.cameraMovedInLastFrame, !box.hasNewCamera, !box.isFlying else {
                return false
            }
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
        afterTake?(self)
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
            box.isFlying = result.isFlying
            box.isTextInFrame = false
            box.areCardsInFrame = false
            box.arePreviewsInFrame = false
            box.previewUploadsWaiting = result.previewUploadsWaiting
            // Without a source, the wanted previews never go to a loader (D-97).
            box.hasPreviewsToRequest = previewSource != nil && result.hasPreviewsToRequest
            if box.spareEraserSamples.capacity < samples.capacity {
                box.spareEraserSamples = samples
            }
        }
        requestPreviews()
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
        let isFlying = stepFlight(renderer, at: deadline ?? start)
        var needsMore = false
        var record: FrameRecord?
        if !input.hasChange && !isFlying && !renderer.needsMoreFrames {
            var result = FrameResult(didDraw: false, needsMore: false, count: renderer.store.count)
            result.previewUploadsWaiting = renderer.previews?.pending.count ?? 0
            result.hasPreviewsToRequest = renderer.hasPreviewsToRequest
            return result
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
            needsMore: needsMore || isFlying,
            count: renderer.store.count,
            record: record,
            isFlying: isFlying,
            previewUploadsWaiting: renderer.previews?.pending.count ?? 0,
            hasPreviewsToRequest: renderer.hasPreviewsToRequest
        )
    }

    /// Runs `body` with the frame work on the calling thread, for work outside the frame loop.
    func withRenderer<Result: Sendable, Failure: Error>(
        _ body: (inout sending FrameRenderer) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        try core.withLock { renderer throws(Failure) -> Result in try body(&renderer) }
    }

    /// Applies the loaded text boxes and the text edits of a frame (D-82).
    private static func applyText(_ input: RenderInput, to renderer: FrameRenderer) {
        // The load comes first, because each edit is newer than the loaded rows.
        if !input.laidOutText.isEmpty {
            renderer.insert(input.laidOutText)
        }
        // An edit counts against a load that is still in flight after this frame.
        renderer.textLoadsInFlight = input.textLoadsInFlight
        if input.textLoadsInFlight == 0 { renderer.textEditedDuringLoad.removeAll() }
        for edit in input.textEdits {
            renderer.apply(edit)
        }
    }

    /// Applies the loaded cards, the card edits, and the previews of a frame, as `applyText`
    /// does for the text.
    private static func applyCards(_ input: RenderInput, to renderer: FrameRenderer) {
        assert(input.cardLoadsInFlight >= 0, "Card loads in flight \(input.cardLoadsInFlight)")
        if let reserve = input.cardReserve {
            renderer.cards.reserveCapacity(reserve)
        }
        if !input.laidOutCards.isEmpty {
            renderer.insert(input.laidOutCards)
        }
        renderer.cards.loadsInFlight = input.cardLoadsInFlight
        if input.cardLoadsInFlight == 0 { renderer.cards.editedDuringLoad.removeAll() }
        for edit in input.cardEdits {
            renderer.apply(edit)
        }
        renderer.makePreviewAtlasIfNeeded()
        renderer.takePreviews(input.decodedPreviews)
        if let request = input.previewRender { renderer.startPreviewRender(request) }
        applyTransition(input, to: renderer)
        assert(renderer.cards.count <= Limits.maxNodesPerCanvas, "The cards keep the node limit")
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
        applyText(input, to: renderer)
        applyCards(input, to: renderer)
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
    /// `true` if the frame drew.
    let didDraw: Bool
    /// `true` if the frame needs another frame.
    let needsMore: Bool
    /// The number of strokes in the store.
    let count: Int
    /// The record of the frame, or `nil`.
    var record: FrameRecord?
    /// `true` while a flight of the camera runs or changed the frame (D-121).
    var isFlying = false
    /// The decoded previews that wait for their upload after the frame (D-97).
    var previewUploadsWaiting = 0
    /// `true` if the frame left preview requests for the loader (D-97).
    var hasPreviewsToRequest = false
}
