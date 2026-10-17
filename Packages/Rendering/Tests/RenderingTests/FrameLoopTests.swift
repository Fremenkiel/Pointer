import Geometry
import Model
import UIKit
import XCTest

@testable import Rendering

/// Pan and zoom on the screen for 4 seconds with the renderer of the app (docs/m2-fix-plan.md,
/// phase 0, task 3). The tests need the display of a device, so the simulator skips them.
@MainActor
final class FrameLoopTests: XCTestCase {
    func testPanDenseStrokes() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        try run(.pan, content: content, name: "dense 20k pan")
    }

    func testZoomDenseStrokes() throws {
        let content = PerformanceContent.dense(count: 20_000, points: 300)
        try run(.zoom, content: content, name: "dense 20k zoom")
    }

    func testPanFewStrokes() throws {
        let content = PerformanceContent.dense(count: 10, points: 300)
        try run(.pan, content: content, name: "few pan")
    }

    func testPanHandwriting() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        try run(.pan, content: content, name: "handwriting 200k pan")
    }

    func testZoomHandwriting() throws {
        let content = PerformanceContent.handwriting(count: 200_000)
        try run(.zoom, content: content, name: "handwriting 200k zoom")
    }

    private func run(_ motion: FrameLoopMotion, content: [Stroke], name: String) throws {
        let window = try hostWindow()
        let view = FrameLoopView(frame: window.bounds)
        window.addSubview(view)
        defer { view.removeFromSuperview() }
        let renderer = try CanvasRenderer()
        renderer.load(content)
        try setUp(renderer, view: view)
        let start = Camera(center: .zero, zoom: Limits.minZoom)
        renderer.camera = start
        let probe = FrameLoopProbe(renderer: renderer, view: view, motion: motion, start: start)
        let report = probe.run()
        XCTContext.runActivity(named: "\(name): \(report)") { _ in }
        XCTAssertGreaterThan(report.frames, 0, "The frame loop drew no measured frame")
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
        #if targetEnvironment(simulator)
            throw XCTSkip("The frame loop needs the display of a device.")
        #else
            // Only UIApplication reaches the window of the host app. The product owner allowed
            // this one use in the frame-loop test on 2026-10-17 (D-44).
            // swiftlint:disable:next arch_05_singletons
            let scenes = UIApplication.shared.connectedScenes
            let window = scenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
            return try XCTUnwrap(window, "The test host has no window")
        #endif
    }
}
