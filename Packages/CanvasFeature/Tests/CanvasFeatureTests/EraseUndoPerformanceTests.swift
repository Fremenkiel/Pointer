import Foundation
import Geometry
import Model
import QuartzCore
import Rendering
import UIKit
import XCTest

@testable import CanvasFeature

/// M4 acceptance 2: erase, undo, and redo of 1,000 strokes in one gesture take under 33 ms per
/// step on the device (D-69). The clock runs from the pencil lift or the undo or redo call until
/// the GPU completes the first frame that holds the result (D-74). The simulator skips it.
@MainActor
final class EraseUndoPerformanceTests: XCTestCase {
    /// The budget of one step, in milliseconds: four display frames at 120 Hz (D-75).
    private static let budgetMilliseconds = 33.0
    /// The rounds of erase, undo, and redo.
    private static let rounds = 5
    /// The parallel strokes that the eraser line cuts in two.
    private static let parallelCount = 1_000
    private static let pointsPerStroke = 300
    /// The camera: 1,500 canvas points of parallel strokes fit on the screen at zoom 0.5.
    private static let camera = Camera(center: .zero, zoom: 0.5)
    private static let timeout = Duration.seconds(5)
    /// The main-thread time of each step call, without the wait for the frame.
    private var callMilliseconds: [Double] = []

    func testEraseUndoRedoOfOneThousandStrokes() async throws {
        let host = try OnScreenCanvas.host()
        let renderer = try CanvasRenderer()
        var dependencies = CanvasDependencies(
            renderer: renderer,
            clock: Fixtures.clock(),
            content: try Self.content()
        )
        dependencies.camera = Self.camera
        let canvas = CanvasViewController(dependencies: dependencies)
        Self.show(canvas, in: host)
        defer { Self.close(canvas) }
        try await settle(renderer)
        // The floor of the frame loop: an empty change, from the call to the GPU end of its frame.
        var empty: [Double] = []
        for _ in 0..<Self.rounds {
            empty.append(
                try await step(canvas, renderer) {
                    renderer.change(
                        removing: [],
                        adding: [],
                        area: nil,
                        onCompleted: { canvas.onStepDrawn?($0) },
                        onPresented: {}
                    )
                }
            )
        }
        var times: [String: [Double]] = ["empty change": empty]
        for _ in 0..<Self.rounds {
            times["erase", default: []].append(try await erase(canvas, renderer: renderer))
            times["undo", default: []].append(try await step(canvas, renderer) { canvas.undo() })
            times["redo", default: []].append(try await step(canvas, renderer) { canvas.redo() })
            _ = try await step(canvas, renderer) { canvas.undo() }
        }
        let calls = callMilliseconds.map { String(format: "%.1f", $0) }
        XCTContext.runActivity(named: "calls: " + calls.joined(separator: " ")) { _ in }
        _ = report(times["empty change"] ?? [], name: "empty change")
        for name in ["erase", "undo", "redo"] {
            let (slowest, line) = report(times[name] ?? [], name: name)
            XCTAssertLessThan(slowest, Self.budgetMilliseconds, line)
        }
    }

    /// Writes the median and the slowest time of a step as an activity.
    ///
    /// - Returns: The slowest time and the line.
    private func report(_ values: [Double], name: String) -> (slowest: Double, line: String) {
        let sorted = values.sorted()
        let line = String(
            format: "%@: median %.2f ms, slowest %.2f ms over %d steps",
            name,
            sorted.isEmpty ? 0 : sorted[sorted.count / 2],
            sorted.last ?? 0,
            sorted.count
        )
        XCTContext.runActivity(named: line) { _ in }
        return (sorted.last ?? .infinity, line)
    }

    private static func show(_ canvas: CanvasViewController, in host: UIViewController) {
        host.addChild(canvas)
        canvas.view.frame = host.view.bounds
        host.view.addSubview(canvas.view)
        canvas.didMove(toParent: host)
        canvas.view.layoutIfNeeded()
    }

    private static func close(_ canvas: CanvasViewController) {
        canvas.willMove(toParent: nil)
        canvas.view.removeFromSuperview()
        canvas.removeFromParent()
    }

    /// The 20,000 strokes of D-56 and 1,000 parallel strokes of 300 points, 1.5 points apart.
    private static func content() throws -> CanvasContent {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        let device = Fixtures.device
        let small = InkPoints(
            (0..<pointsPerStroke).map {
                InkPoint(x: Float($0) / 10, y: Float($0 % 7), force: 0.5, time: 0)
            }
        )
        for index in 0..<20_000 {
            try content.add(
                stroke(
                    origin: Point(
                        x: Double(index % 200) * 40 - 4_000,
                        y: Double(index / 200) * 40 - 2_000
                    ),
                    points: small,
                    counter: index,
                    device: device
                )
            )
        }
        let long = InkPoints(
            (0..<pointsPerStroke).map {
                InkPoint(x: Float($0) * 2, y: 0, force: 0.5, time: Float($0) / 240)
            }
        )
        for row in 0..<parallelCount {
            try content.add(
                stroke(
                    origin: Point(x: -300, y: Double(row) * 1.5 - 750),
                    points: long,
                    counter: 20_000 + row,
                    device: device
                )
            )
        }
        return content
    }

    private static func stroke(
        origin: Point,
        points: InkPoints,
        counter: Int,
        device: DeviceID
    ) -> Stroke {
        Stroke(
            id: StrokeID(rawValue: UUID()),
            canvasID: Fixtures.canvas,
            created: HybridTimestamp(wallMillis: 1, counter: UInt32(counter), device: device),
            origin: origin,
            width: 2,
            points: points
        )
    }

    /// Waits until the renderer has drawn all strokes and needs no frame.
    private func settle(_ renderer: CanvasRenderer) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.timeout)
        while renderer.needsMoreFrames {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(200))
    }

    /// Runs one eraser gesture down the canvas line x = 0 and times the lift.
    private func erase(
        _ canvas: CanvasViewController,
        renderer: CanvasRenderer
    ) async throws -> Double {
        canvas.select(.eraser)
        canvas.pencilBegan()
        let size = Size(width: canvas.view.bounds.width, height: canvas.view.bounds.height)
        for step in 0...260 {
            let point = Self.camera.viewPoint(
                fromCanvas: Point(x: 0, y: Double(step) * 6 - 780),
                viewSize: size
            )
            canvas.pencilMoved(to: point)
        }
        try await settle(renderer)
        let before = canvas.content.strokes.count
        let time = try await step(canvas, renderer) {
            canvas.pencilEnded(at: 0, isCancelled: false)
        }
        // The line also cuts a few strokes of the D-56 grid.
        XCTAssertGreaterThanOrEqual(canvas.content.strokes.count, before + Self.parallelCount)
        return time
    }

    /// Runs `action` and returns the milliseconds until the GPU completes the first frame that
    /// holds it. `gpuEndTime` and `CACurrentMediaTime()` use the same host clock.
    private func step(
        _ canvas: CanvasViewController,
        _ renderer: CanvasRenderer,
        _ action: () -> Void
    ) async throws -> Double {
        var end: Double?
        canvas.onStepDrawn = { end = $0 }
        let start = CACurrentMediaTime()
        action()
        callMilliseconds.append((CACurrentMediaTime() - start) * 1_000)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.timeout)
        while end == nil {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(1))
        }
        canvas.onStepDrawn = nil
        let milliseconds = ((end ?? start) - start) * 1_000
        try await settle(renderer)
        return milliseconds
    }
}
