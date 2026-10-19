import Model
import Rendering
import UIKit
import XCTest
import os

@testable import CanvasFeature

/// The result of one open of a canvas on the screen.
struct OpenMeasurement {
    /// The time of the load from the library, in milliseconds.
    let loadMilliseconds: Double
    /// The time from the start of the load to the end of the first frame that holds all
    /// strokes, in milliseconds.
    let totalMilliseconds: Double
    /// The memory growth from the start of the load to the end of that frame, in MB.
    let heldMegabytes: Double
    /// The largest memory growth during the open, in MB.
    let peakMegabytes: Double
}

/// The open did not reach a frame with all strokes in time.
struct OpenTimedOut: Error {}

/// Opens a canvas on the screen of the device as the app does at a workspace switch: the load
/// from the library, the canvas screen in the window, and the render thread up to the first
/// frame that holds all strokes (architecture.md section 12).
@MainActor
enum OnScreenCanvas {
    /// The wait between two looks at the renderer.
    private static let pollInterval = Duration.milliseconds(1)
    /// The longest open before the test fails. The budget is 300 ms.
    private static let timeout = Duration.seconds(5)
    /// The wait after a close, so that the render thread of the closed canvas stops.
    private static let settleTime = Duration.milliseconds(500)
    private static let bytesPerMegabyte = 1_048_576.0

    /// Returns the root view controller of the test host window. The simulator skips.
    ///
    /// - Throws: `XCTSkip` on the simulator, or an error if the host has no window.
    static func host() throws -> UIViewController {
        #if targetEnvironment(simulator)
            throw XCTSkip("Open times and memory are valid on a device only.")
        #else
            // Only UIApplication reaches the window of the host app. The product owner allowed
            // this one use in the open and memory tests on 2026-10-19 (D-62).
            // swiftlint:disable:next arch_05_singletons
            let scenes = UIApplication.shared.connectedScenes
            let window = scenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
            return try XCTUnwrap(window?.rootViewController, "The test host has no window")
        #endif
    }

    /// Opens the canvas of `library` in `host`, measures the open, and closes the canvas.
    ///
    /// - Throws: An error of the load or the renderer, or `OpenTimedOut`.
    static func open(
        _ library: D56Library,
        in host: UIViewController
    ) async throws -> OpenMeasurement {
        let clock = ContinuousClock()
        let available = os_proc_available_memory()
        var lowest = available
        let start = clock.now
        let content = try await library.repository.content(of: library.canvas)
        let loaded = clock.now
        let renderer = try CanvasRenderer()
        var dependencies = CanvasDependencies(
            renderer: renderer,
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.repository = library.repository
        let canvas = CanvasViewController(dependencies: dependencies)
        show(canvas, in: host)
        let deadline = start.advanced(by: timeout)
        while renderer.needsMoreFrames || renderer.strokeCount < content.strokes.count {
            guard clock.now < deadline else { throw OpenTimedOut() }
            lowest = min(lowest, os_proc_available_memory())
            try await Task.sleep(for: pollInterval)
        }
        let end = clock.now
        let held = os_proc_available_memory()
        close(canvas)
        try await Task.sleep(for: settleTime)
        return OpenMeasurement(
            loadMilliseconds: start.duration(to: loaded) / .milliseconds(1),
            totalMilliseconds: start.duration(to: end) / .milliseconds(1),
            heldMegabytes: megabytes(available - min(available, held)),
            peakMegabytes: megabytes(available - min(lowest, held))
        )
    }

    /// Adds the canvas as `AppViewController.show(_:)` does.
    private static func show(_ canvas: CanvasViewController, in host: UIViewController) {
        host.addChild(canvas)
        canvas.view.frame = host.view.bounds
        host.view.addSubview(canvas.view)
        canvas.didMove(toParent: host)
        canvas.view.layoutIfNeeded()
    }

    /// Removes the canvas as `AppViewController.show(_:)` removes the old one.
    private static func close(_ canvas: CanvasViewController) {
        canvas.willMove(toParent: nil)
        canvas.view.removeFromSuperview()
        canvas.removeFromParent()
    }

    private static func megabytes(_ bytes: Int) -> Double {
        Double(bytes) / bytesPerMegabyte
    }
}
