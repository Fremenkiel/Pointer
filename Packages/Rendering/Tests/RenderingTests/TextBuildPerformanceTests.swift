import Darwin
import Geometry
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The CPU time and the frame count of a whole build of the D-56 text at zoom 0.25 and 1 (D-94,
/// D-105, m10-plan.md task 4.1). The build of the text at zoom 0.25 took 9.3 to 10.2 ms of CPU
/// against a budget of 2 ms per frame after the review of M5. The test records the measures and
/// does not fail on them: the design of task 4.1 sets the target.
@MainActor
final class TextBuildPerformanceTests: XCTestCase {
    /// The screen of the iPad Pro 11-inch (M4) in landscape, in points.
    private static let viewSize = Size(width: 1_210, height: 834)
    private static let displayScale = 2.0
    /// The most frames of one build.
    private static let maxFrames = 600

    func testBuildOfD56Text() throws {
        let renderer = try CanvasRenderer()
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(
            width: Self.viewSize.width * Self.displayScale,
            height: Self.viewSize.height * Self.displayScale
        )
        renderer.setViewport(viewSize: Self.viewSize, displayScale: Self.displayScale)
        renderer.load(try PerformanceContent.textBoxes(count: 5_000))
        for _ in 0..<2_000 {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            guard renderer.isLoadingText else { break }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        XCTAssertFalse(renderer.isLoadingText, "The text loaded")
        var values: [String: Double] = [:]
        for zoom in [Limits.minZoom, Limits.standardZoom] {
            // The third build goes back to the place of the first one, where the runs exist.
            let centers = [Point(x: -1_000, y: 0), Point(x: 1_000, y: 0), Point(x: -1_000, y: 0)]
            for (index, center) in centers.enumerated() {
                let camera = Camera(center: center, zoom: zoom)
                let build = try measureBuild(renderer, layer, camera: camera)
                let line = String(
                    format: "text build, zoom %.2f, run %d: CPU %.2f ms, %d frames, max %.2f ms",
                    zoom,
                    index + 1,
                    build.cpu,
                    build.frames,
                    build.slowest
                )
                XCTContext.runActivity(named: line) { _ in }
                guard index > 0 else { continue }
                // Run 2 keeps the keys of the baseline. Run 3 is the build where the runs exist.
                let key = (zoom < 1 ? "zoom-0.25" : "zoom-1") + (index == 2 ? ".back" : "")
                values["\(key).cpu.ms"] = build.cpu
                values["\(key).slowest.ms"] = build.slowest
                values["\(key).frames.count"] = Double(build.frames)
            }
        }
        PerformanceRecord.attach(values)
    }

    /// The CPU time, the frames, and the slowest frame of one build.
    private struct Build {
        let cpu: Double
        let frames: Int
        let slowest: Double
    }

    /// Moves the camera and draws frames until the renderer needs none.
    private func measureBuild(
        _ renderer: CanvasRenderer,
        _ layer: CAMetalLayer,
        camera: Camera
    ) throws -> Build {
        renderer.camera = camera
        var cpu = 0.0
        var slowest = 0.0
        var frames = 0
        while frames < Self.maxFrames {
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let needsMore = renderer.renderFrame(into: layer, deadline: nil)
            let milliseconds = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start) / 1e6
            cpu += milliseconds
            slowest = max(slowest, milliseconds)
            frames += 1
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.004))
            guard needsMore else { break }
        }
        XCTAssertLessThan(frames, Self.maxFrames, "The build ends")
        return Build(cpu: cpu, frames: frames, slowest: slowest)
    }
}
