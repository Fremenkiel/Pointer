import Geometry
import Model
import QuartzCore
import Synchronization
import UIKit
import XCTest

@testable import Rendering

/// Pan and zoom on the screen for 4 seconds with the renderer of the app (docs/m2-fix-plan.md,
/// phase 0, task 3). The tests need the display of a device, so they run on the iPad only (D-77).
@MainActor
final class FrameLoopTests: XCTestCase {
    func testPanDenseStrokes() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        _ = try run(.pan, content: content, name: "dense 20k pan")
    }

    func testZoomDenseStrokes() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        _ = try run(.zoom, content: content, name: "dense 20k zoom")
    }

    func testFastPanDenseStrokes() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        _ = try run(.fastPan, content: content, name: "dense 20k fast pan")
    }

    func testPanFewStrokes() throws {
        let content = PerformanceContent.dense(count: 10, points: 300)
        _ = try run(.pan, content: content, name: "few pan")
    }

    func testPanHandwriting() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        _ = try run(.pan, content: content, name: "handwriting 200k pan")
    }

    func testZoomHandwriting() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        _ = try run(.zoom, content: content, name: "handwriting 200k zoom")
    }

    func testPanText() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        let text = try PerformanceContent.textBoxes(count: 5_000)
        _ = try run(.pan, content: content, text: text, name: "D-56 text pan")
    }

    func testZoomText() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        let text = try PerformanceContent.textBoxes(count: 5_000)
        _ = try run(.zoom, content: content, text: text, name: "D-56 text zoom")
    }

    func testPanCards() throws {
        try runCards(.pan, zoom: Limits.minZoom, name: "D-56 cards pan")
    }

    func testZoomCards() throws {
        try runCards(.zoom, zoom: Limits.minZoom, name: "D-56 cards zoom")
    }

    func testPanCardsAtZoomOne() throws {
        try runCards(.pan, zoom: Limits.standardZoom, name: "D-56 cards pan at zoom 1")
    }

    /// The strokes and the 5,000 cards of D-56 with previews from a source, as the app has them
    /// (m6-plan.md task 3.6). The previews load during the warm-up and the measure.
    private func runCards(_ motion: FrameLoopMotion, zoom: Double, name: String) throws {
        let previews = FakePreviews(data: try FakePreviews.png(width: 300, height: 210))
        let report = try run(
            motion,
            content: PerformanceContent.dense(count: 20_000, points: 300),
            cards: try PerformanceContent.cards(count: 5_000),
            previews: previews,
            zoom: zoom,
            name: name
        )
        // The previews arrive during the whole run. They must not stop the builds.
        XCTAssertGreaterThan(report.builds, 0, "\(name): no build completed")
    }

    /// The preview render of the D-56 content at a leave: the time from the request to the
    /// image, and the frames of the canvas during it (m6-plan.md task 3.4).
    func testPreviewRenderOfD56() throws {
        let window = try hostWindow()
        let view = FrameLoopView(frame: window.bounds)
        window.addSubview(view)
        defer { view.removeFromSuperview() }
        let renderer = try CanvasRenderer()
        renderer.load(PerformanceContent.dense(count: 20_000, points: 300))
        renderer.load(try PerformanceContent.textBoxes(count: 5_000))
        try setUp(renderer, view: view)
        for _ in 0..<5_000 where renderer.isLoadingText || renderer.isLoadingCards {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        let start = Camera(center: .zero, zoom: Limits.standardZoom)
        renderer.camera = start
        let times = Mutex<(start: Double, end: Double)>((0, 0))
        let probe = FrameLoopProbe(renderer: renderer, view: view, motion: .still, start: start)
        probe.onMeasureStart = {
            times.withLock { $0.start = CACurrentMediaTime() }
            renderer.renderPreview(camera: start, cardAspect: 1194.0 / 834.0) { image in
                times.withLock { $0.end = image == nil ? -1 : CACurrentMediaTime() }
            }
        }
        let report = probe.run()
        let (begin, end) = times.withLock { ($0.start, $0.end) }
        let line = String(
            format: "D-56 preview render: %.1f ms; %@",
            (end - begin) * 1000,
            report.description
        )
        XCTContext.runActivity(named: line) { _ in }
        var samples = report.samples
        samples["preview.ms"] = (end - begin) * 1000
        // The frames of the preview render present no drawable, so the probe measures no GPU
        // time for them. `preview.ms` holds the GPU work of the render.
        samples["gpu.p50.ms"] = nil
        samples["gpu.p99.ms"] = nil
        PerformanceRecord.attach(samples)
        XCTAssertGreaterThan(end, begin, "The preview arrived in the measured time")
        XCTAssertEqual(report.lateIntervals, 0, line)
        // The preview render draws off the screen, so a still canvas presents no frame for it.
        // The present of an unchanged frame after an idle of the display showed late or never
        // (m10-plan.md section 6.44).
        XCTAssertGreaterThan(report.frames, 0, "The preview render ran in frames")
        XCTAssertEqual(report.presentedTimes.count, 0, "A still canvas presents no frame")
        XCTAssertEqual(report.droppedFrames, 0, "No frame of the preview render was dropped")
    }

    private func run(
        _ motion: FrameLoopMotion,
        content: [Stroke],
        text: [TextBox] = [],
        cards: [Card] = [],
        previews: (any PreviewSource)? = nil,
        zoom: Double = Limits.minZoom,
        name: String
    ) throws -> FrameLoopReport {
        let window = try hostWindow()
        let view = FrameLoopView(frame: window.bounds)
        window.addSubview(view)
        defer { view.removeFromSuperview() }
        let renderer = try CanvasRenderer(previews: previews)
        renderer.load(content)
        renderer.load(text)
        renderer.load(cards)
        try setUp(renderer, view: view)
        // The text layout runs off the render thread (D-92). The measure starts after it.
        for _ in 0..<5_000 where renderer.isLoadingText || renderer.isLoadingCards {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        let start = Camera(center: .zero, zoom: zoom)
        renderer.camera = start
        let probe = FrameLoopProbe(renderer: renderer, view: view, motion: motion, start: start)
        let report = probe.run()
        XCTContext.runActivity(named: "\(name): \(report)") { _ in }
        PerformanceRecord.attach(report.samples)
        // The previews of the cards load during the run. They end before the next test.
        for _ in 0..<5_000 where renderer.isLoadingPreviews {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        XCTAssertGreaterThan(report.frames, 0, "The frame loop drew no measured frame")
        return report
    }

    private func setUp(_ renderer: CanvasRenderer, view: FrameLoopView) throws {
        let metalLayer = try XCTUnwrap(view.layer as? CAMetalLayer)
        let scale = view.traitCollection.displayScale
        renderer.configure(metalLayer)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: view.bounds.width * scale,
            height: view.bounds.height * scale
        )
        let viewSize = Size(width: view.bounds.width, height: view.bounds.height)
        renderer.setViewport(viewSize: viewSize, displayScale: scale)
    }

    private func hostWindow() throws -> UIWindow {
        // Only UIApplication reaches the window of the host app. The product owner allowed
        // this one use in the frame-loop test on 2026-10-17 (D-44).
        // swiftlint:disable:next arch_05_singletons
        let scenes = UIApplication.shared.connectedScenes
        let window = scenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
        return try XCTUnwrap(window, "The test host has no window")
    }
}
