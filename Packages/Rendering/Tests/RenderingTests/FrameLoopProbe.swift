import Geometry
import Metal
import QuartzCore
import Synchronization
import UIKit

@testable import Rendering

/// A view with a Metal layer and no frame loop of its own.
final class FrameLoopView: UIView {
    override static var layerClass: AnyClass { CAMetalLayer.self }
}

/// The camera motion of a frame-loop run.
enum FrameLoopMotion {
    case pan
    case fastPan
    case zoom

    /// The pan turns back after this many seconds, as in the benchmark.
    fileprivate static let panLeg = 0.75
    /// The pan speed, in view points per second.
    private static let panSpeed = Vector(dx: 1500, dy: 500)
    /// The fast pan speed: 2,000 view points per second, the top speed of phase 2, task 4.
    private static let fastPanSpeed = Vector(dx: 1897, dy: 632)

    /// Returns the camera at `elapsed` seconds after the start.
    func camera(at elapsed: Double, start: Camera) -> Camera {
        switch self {
        case .pan:
            return Self.pan(at: elapsed, speed: Self.panSpeed, start: start)
        case .fastPan:
            return Self.pan(at: elapsed, speed: Self.fastPanSpeed, start: start)
        case .zoom:
            // Zoom between 0.25 and 0.49, as in the benchmark.
            return Camera(center: start.center, zoom: 0.35 * pow(1.4, sin(elapsed * .pi)))
        }
    }
}

extension FrameLoopMotion {
    fileprivate static func pan(at elapsed: Double, speed: Vector, start: Camera) -> Camera {
        let phase = elapsed.truncatingRemainder(dividingBy: 2 * panLeg)
        let leg = phase < panLeg ? phase : 2 * panLeg - phase
        return start.panned(byView: Vector(dx: speed.dx * leg, dy: speed.dy * leg))
    }
}

/// Collects the measurements of the render thread during a run.
final class FrameLoopCollector: FrameObserving {
    private struct State {
        var window: ClosedRange<Double> = 0...0
        var frameIndex = 0
        var presented: [Double] = []
        var gpu: [Double] = []
        var allocations: [Double] = []
        var renderThread: [Double] = []
        var builds = 0
        var uncovered = 0
        var frames = 0
        var lastFront: ObjectIdentifier?
    }

    private let state = Mutex(State())
    private let viewSize: Size

    /// Makes a collector for a view of `viewSize` points.
    init(viewSize: Size) {
        self.viewSize = viewSize
    }

    /// Sets the measured time, in `CACurrentMediaTime()` seconds.
    func measure(from start: Double, to end: Double) {
        state.withLock { $0.window = start...end }
    }

    /// Even frames measure the GPU time and odd frames the allocations, because the GPU handler
    /// allocates.
    func measure(_ work: () -> Void) {
        let countsAllocations = state.withLock { state in
            state.frameIndex += 1
            return !state.frameIndex.isMultiple(of: 2)
        }
        guard countsAllocations else {
            work()
            return
        }
        let count = AllocationCounter.count(work)
        state.withLock { state in
            if let count, state.window.contains(CACurrentMediaTime()) {
                state.allocations.append(Double(count))
            }
        }
    }

    func willCommit(_ commandBuffer: any MTLCommandBuffer, drawable: any CAMetalDrawable) {
        let measuresGPU = state.withLock { $0.frameIndex.isMultiple(of: 2) }
        #if targetEnvironment(simulator)
            // The simulator has no presented handler. The frame-loop tests skip it.
        #else
            drawable.addPresentedHandler { [self] presented in
                record(presentedAt: presented.presentedTime)
            }
        #endif
        guard measuresGPU else { return }
        commandBuffer.addCompletedHandler { [self] buffer in
            let milliseconds = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            state.withLock {
                if $0.window.contains(buffer.gpuEndTime) { $0.gpu.append(milliseconds) }
            }
        }
    }

    /// A presented time of 0 marks a frame that the display never showed.
    private func record(presentedAt time: Double) {
        state.withLock { if time > 0 && $0.window.contains(time) { $0.presented.append(time) } }
    }

    func didRender(_ record: FrameRecord) {
        let visible = record.camera.visibleRect(viewSize: viewSize)
        state.withLock { state in
            guard state.window.contains(record.targetTime) else {
                state.lastFront = record.front
                return
            }
            state.frames += 1
            state.renderThread.append(record.cpuMilliseconds)
            if record.front != state.lastFront { state.builds += 1 }
            state.lastFront = record.front
            guard let covered = record.frontRect else {
                state.uncovered += 1
                return
            }
            let isCovered =
                visible.minX >= covered.minX && visible.maxX <= covered.maxX
                && visible.minY >= covered.minY && visible.maxY <= covered.maxY
            if !isCovered { state.uncovered += 1 }
        }
    }

    /// Fills the render-thread values of a report.
    func fill(_ report: inout FrameLoopReport) {
        state.withLock { state in
            let times = state.presented.sorted()
            report.intervals = zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }
            report.gpu = state.gpu
            report.allocations = state.allocations
            report.renderThread = state.renderThread
            report.builds = state.builds
            report.uncoveredFrames = state.uncovered
            report.frames = state.frames
        }
    }
}

/// Drives a renderer on its render thread as `InkView` does, moves the camera from a main-thread
/// `UIUpdateLink` as a pan does, and measures each frame (docs/m2-fix-plan.md, phase 0, task 3).
@MainActor
final class FrameLoopProbe {
    /// The seconds before the measurement starts.
    static let warmUp = 1.0
    /// The measured seconds.
    static let duration = 4.0
    /// The run loop turns of one run at most, 10 ms each.
    static let maxRunLoopTurns = 1_000

    private let renderer: CanvasRenderer
    private let view: FrameLoopView
    private let motion: FrameLoopMotion
    private let start: Camera
    private let collector: FrameLoopCollector
    private var startTime: Double?
    private var isDone = false
    private var mainThread: [Double] = []

    /// Makes a probe for a renderer that draws into the layer of `view`.
    init(renderer: CanvasRenderer, view: FrameLoopView, motion: FrameLoopMotion, start: Camera) {
        self.renderer = renderer
        self.view = view
        self.motion = motion
        self.start = start
        collector = FrameLoopCollector(
            viewSize: Size(width: view.bounds.width, height: view.bounds.height)
        )
    }

    /// Runs the frame loop for the warm-up and the measured time.
    ///
    /// - Returns: The measurements of the measured time.
    func run() -> FrameLoopReport {
        guard let layer = view.layer as? CAMetalLayer else {
            preconditionFailure("The layer class of FrameLoopView is CAMetalLayer")
        }
        let collector = collector
        renderer.engine.post { $0.observer = collector }
        let thread = RenderThread(
            engine: renderer.engine,
            layer: layer,
            frameRates: InkView.frameRates
        )
        thread.start()
        let link = UIUpdateLink(view: view)
        link.addAction(to: .afterCADisplayLinkDispatch) { [weak self] _, info in
            self?.tick(info)
        }
        link.preferredFrameRateRange = InkView.frameRates
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        for _ in 0..<Self.maxRunLoopTurns where !isDone {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        link.isEnabled = false
        thread.stop()
        renderer.engine.post { $0.observer = nil }
        var report = FrameLoopReport()
        collector.fill(&report)
        report.mainThread = mainThread
        return report
    }

    private func tick(_ info: UIUpdateInfo) {
        let now = info.modelTime
        if startTime == nil {
            startTime = now
            collector.measure(from: now + Self.warmUp, to: now + Self.warmUp + Self.duration)
        }
        let elapsed = now - (startTime ?? now)
        guard elapsed <= Self.warmUp + Self.duration else {
            isDone = true
            return
        }
        let begin = CACurrentMediaTime()
        renderer.camera = motion.camera(at: elapsed, start: start)
        if elapsed >= Self.warmUp {
            mainThread.append((CACurrentMediaTime() - begin) * 1000)
        }
    }
}
