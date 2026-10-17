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
    case zoom

    /// The pan turns back after this many seconds, as in the benchmark.
    private static let panLeg = 0.75
    /// The pan speed, in view points per second.
    private static let panSpeed = Vector(dx: 1500, dy: 500)

    /// Returns the camera at `elapsed` seconds after the start.
    func camera(at elapsed: Double, start: Camera) -> Camera {
        switch self {
        case .pan:
            let phase = elapsed.truncatingRemainder(dividingBy: 2 * Self.panLeg)
            let leg = phase < Self.panLeg ? phase : 2 * Self.panLeg - phase
            let offset = Vector(dx: Self.panSpeed.dx * leg, dy: Self.panSpeed.dy * leg)
            return start.panned(byView: offset)
        case .zoom:
            // Zoom between 0.25 and 0.49, as in the benchmark.
            return Camera(center: start.center, zoom: 0.35 * pow(1.4, sin(elapsed * .pi)))
        }
    }
}

/// A sendable list of GPU times that completed handlers fill.
final class GPUTimeLog: Sendable {
    private let values = Mutex<[Double]>([])

    /// Adds a time in milliseconds.
    func append(_ value: Double) { values.withLock { $0.append(value) } }

    /// All times in the order of completion.
    var all: [Double] { values.withLock { $0 } }
}

/// Drives a renderer with a `UIUpdateLink` as `InkView` does, moves the camera, and measures each
/// frame (docs/m2-fix-plan.md, phase 0, task 3).
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
    private let gpuTimes = GPUTimeLog()
    private let gpuHandler: (any MTLCommandBuffer) -> Void
    private var startTime: Double?
    private var lastTime: Double?
    private var lastFront: ObjectIdentifier?
    private var frameIndex = 0
    private var isDone = false
    private var report = FrameLoopReport()

    /// Makes a probe for a renderer that draws into the layer of `view`.
    init(renderer: CanvasRenderer, view: FrameLoopView, motion: FrameLoopMotion, start: Camera) {
        self.renderer = renderer
        self.view = view
        self.motion = motion
        self.start = start
        let times = gpuTimes
        gpuHandler = { commandBuffer in
            commandBuffer.addCompletedHandler { buffer in
                times.append((buffer.gpuEndTime - buffer.gpuStartTime) * 1000)
            }
        }
    }

    /// Runs the frame loop for the warm-up and the measured time.
    ///
    /// - Returns: The measurements of the measured time.
    func run() -> FrameLoopReport {
        let link = UIUpdateLink(view: view)
        link.addAction(to: .afterCADisplayLinkDispatch) { [weak self] _, info in
            self?.tick(info)
        }
        link.wantsLowLatencyEventDispatch = false
        link.wantsImmediatePresentation = false
        link.preferredFrameRateRange = InkView.frameRates
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        for _ in 0..<Self.maxRunLoopTurns where !isDone {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        link.isEnabled = false
        report.gpu = gpuTimes.all
        return report
    }

    private var metalLayer: CAMetalLayer {
        guard let layer = view.layer as? CAMetalLayer else {
            preconditionFailure("The layer class of FrameLoopView is CAMetalLayer")
        }
        return layer
    }

    private func tick(_ info: UIUpdateInfo) {
        let now = info.modelTime
        let elapsed = now - (startTime ?? now)
        startTime = startTime ?? now
        guard elapsed <= Self.warmUp + Self.duration else {
            isDone = true
            return
        }
        let isMeasured = elapsed >= Self.warmUp
        if isMeasured, let lastTime {
            report.intervals.append((now - lastTime) * 1000)
        }
        lastTime = now
        renderer.camera = motion.camera(at: elapsed, start: start)
        renderFrame(info, isMeasured: isMeasured)
    }

    /// Even frames measure the GPU time and odd frames the allocations, because the GPU handler
    /// allocates.
    private func renderFrame(_ info: UIUpdateInfo, isMeasured: Bool) {
        frameIndex += 1
        let measuresGPU = frameIndex.isMultiple(of: 2)
        renderer.onCommit = isMeasured && measuresGPU ? gpuHandler : nil
        let begin = CACurrentMediaTime()
        let allocations = AllocationCounter.count {
            renderer.renderFrame(into: metalLayer, deadline: info.completionDeadlineTime)
        }
        let time = (CACurrentMediaTime() - begin) * 1000
        recordLayer(isMeasured: isMeasured)
        guard isMeasured else { return }
        report.frames += 1
        report.mainThread.append(time)
        if !measuresGPU, let allocations {
            report.allocations.append(Double(allocations))
        }
    }

    private func recordLayer(isMeasured: Bool) {
        guard let front = renderer.layer?.front else {
            if isMeasured { report.uncoveredFrames += 1 }
            return
        }
        let identity = ObjectIdentifier(front.texture)
        if isMeasured && identity != lastFront { report.builds += 1 }
        lastFront = identity
        let size = Size(width: view.bounds.width, height: view.bounds.height)
        let visible = renderer.camera.visibleRect(viewSize: size)
        let covered = front.canvasRect
        let isCovered =
            visible.minX >= covered.minX && visible.maxX <= covered.maxX
            && visible.minY >= covered.minY && visible.maxY <= covered.maxY
        if isMeasured && !isCovered { report.uncoveredFrames += 1 }
    }
}
