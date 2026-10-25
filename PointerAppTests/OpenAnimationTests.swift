import Foundation
import Geometry
import Model
import QuartzCore
import Synchronization
import UIKit
import WorkspaceFeature
import XCTest

@testable import CanvasFeature
@testable import Pointer
@testable import Rendering

/// The open of a card of the D-56 canvas with the animation of D-98 (m6-plan.md task 4.5,
/// CARD-03, CAN-05). The test counts the late frames of the parent during the open, and records
/// the largest change of the camera between two frames.
@MainActor
final class OpenAnimationTests: XCTestCase {
    /// The longest wait for a canvas.
    private static let timeout = Duration.seconds(20)
    /// A frame later than this interval is late at 120 Hz (`FrameLoopReport`).
    private static let lateMilliseconds = FrameLoopReport.lateIntervalMilliseconds

    /// The cameras of the frames of a renderer.
    final class Cameras: FrameObserving {
        private let state = Mutex<[Camera]>([])
        private let collector: FrameLoopCollector

        init(collector: FrameLoopCollector) {
            self.collector = collector
        }

        var all: [Camera] { state.withLock { $0 } }

        func measure(_ work: () -> Void) { work() }

        func willCommit(_ commandBuffer: any MTLCommandBuffer, drawable: any CAMetalDrawable) {
            collector.willCommit(commandBuffer, drawable: drawable)
        }

        func didRender(_ record: FrameRecord) {
            state.withLock { $0.append(record.camera) }
            collector.didRender(record)
        }
    }

    func testOpenOfD56CardHasNoLateFrame() async throws {
        let host = try OnScreenCanvas.host()
        let window = try XCTUnwrap(host.view.window as? InputTrackingWindow)
        let library = try await D56Library.make()
        defer { await library.remove() }
        let container = AppViewController()
        let composition = try await Self.composition(of: library, window: window, in: container)
        let hostViews = host.view.subviews
        hostViews.forEach { $0.removeFromSuperview() }
        defer {
            container.view.removeFromSuperview()
            hostViews.forEach { host.view.addSubview($0) }
        }
        container.view.frame = host.view.bounds
        host.view.addSubview(container.view)
        await composition.selector?.start(
            lastWorkspace: WorkspaceID(rawValue: library.canvas.rawValue)
        )
        let parent = try await Self.waitForCanvas(library.canvas, in: composition)
        try await Self.waitForDrawn(parent)
        let card = try XCTUnwrap(Self.cardNearestToCenter(of: parent))
        let open = try await Self.measureOpen(of: card, from: parent, in: composition)
        let samples = Self.flightSamples("open", late: open.late, held: open.held)
        PerformanceRecord.attach(samples, line: open.text)
        XCTAssertEqual(open.late, 0, open.text)
        XCTAssertEqual(open.child.camera.zoom, Limits.standardZoom)
    }

    /// The report line of an open, its late frames, its held frames, and the child.
    struct Measure {
        let text: String
        let late: Int
        let held: Int
        let child: CanvasViewController
    }

    /// Runs the open of `card` and returns its report line, its late frames, and the child.
    static func measureOpen(
        of card: Card,
        from parent: CanvasViewController,
        in composition: AppComposition,
        name: String = "a D-56 card"
    ) async throws -> Measure {
        let viewSize = Size(width: parent.view.bounds.width, height: parent.view.bounds.height)
        let collector = FrameLoopCollector(viewSize: viewSize)
        let cameras = Cameras(collector: collector)
        let start = CACurrentMediaTime()
        collector.measure(from: start, to: start + 5)
        parent.renderer.engine.post { $0.observer = cameras }
        composition.openChild(card)
        let child = try await waitForCanvas(card.childCanvasID, in: composition)
        let end = CACurrentMediaTime()
        let line = reportLine(
            name: name,
            collector: collector,
            cameras: cameras.all,
            viewSize: viewSize,
            milliseconds: (end - start) * 1000
        )
        var report = FrameLoopReport()
        collector.fill(&report)
        return Measure(
            text: line,
            late: report.lateIntervals,
            held: heldFrames(cameras.all),
            child: child
        )
    }

    /// The leave of a D-56 card back to the D-56 canvas (m6-plan.md task 4.6): the late frames
    /// of the child and of the parent, from the tap to the end of the flight of the parent.
    func testLeaveOfD56CardHasNoLateFrame() async throws {
        let host = try OnScreenCanvas.host()
        let window = try XCTUnwrap(host.view.window as? InputTrackingWindow)
        let library = try await D56Library.make()
        defer { await library.remove() }
        let container = AppViewController()
        let composition = try await Self.composition(of: library, window: window, in: container)
        let hostViews = host.view.subviews
        hostViews.forEach { $0.removeFromSuperview() }
        defer {
            container.view.removeFromSuperview()
            hostViews.forEach { host.view.addSubview($0) }
        }
        container.view.frame = host.view.bounds
        host.view.addSubview(container.view)
        await composition.selector?.start(
            lastWorkspace: WorkspaceID(rawValue: library.canvas.rawValue)
        )
        let parent = try await Self.waitForCanvas(library.canvas, in: composition)
        try await Self.waitForDrawn(parent)
        let card = try XCTUnwrap(Self.cardNearestToCenter(of: parent))
        composition.openChild(card)
        let child = try await Self.waitForCanvas(card.childCanvasID, in: composition)
        try await Self.waitForDrawn(child)
        let line = try await Self.measureLeave(of: child, card: card, in: composition)
        let samples = Self.flightSamples("leave", late: line.late, held: line.held)
        PerformanceRecord.attach(samples, line: line.text)
        // The first frames of a leave wait for the driver to wire new memory, and under the load
        // of a full run one of them can miss (D-137). M10 traces the rest of the wait.
        Self.expectNoLateFrame(line.late, line.text, accepted: "D-137")
    }

    /// Runs the leave and returns its report line and its late frames.
    static func measureLeave(
        of child: CanvasViewController,
        card: Card,
        in composition: AppComposition,
        name: String = "a D-56 card"
    ) async throws -> LeaveMeasure {
        let viewSize = Size(width: child.view.bounds.width, height: child.view.bounds.height)
        let childFrames = FrameLoopCollector(viewSize: viewSize)
        let parentFrames = FrameLoopCollector(viewSize: viewSize)
        let start = CACurrentMediaTime()
        childFrames.measure(from: start, to: start + 5)
        parentFrames.measure(from: start, to: start + 5)
        child.renderer.engine.post { $0.observer = Cameras(collector: childFrames) }
        composition.leave()
        let parent = try await waitForCanvas(card.canvasID, in: composition)
        let parentCameras = Cameras(collector: parentFrames)
        parent.renderer.engine.post { $0.observer = parentCameras }
        let target = Camera(center: card.frame.center, zoom: Limits.standardZoom)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while parent.camera != target, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        let end = CACurrentMediaTime()
        var childReport = FrameLoopReport()
        childFrames.fill(&childReport)
        var parentReport = FrameLoopReport()
        parentFrames.fill(&parentReport)
        let late = childReport.lateIntervals + parentReport.lateIntervals
        let held = heldFrames(parentCameras.all)
        let text = String(
            format: "leave of %@: %.0f ms, child %d frames, parent %d frames, late %d, held %d %@",
            name,
            (end - start) * 1000,
            childReport.frames,
            parentReport.frames,
            late,
            held,
            lateDetail(child: childReport, parent: parentReport)
        )
        return LeaveMeasure(text: text, late: late, held: held)
    }

    /// A double tap hits a card on the screen: the card nearest to the screen center.
    private static func cardNearestToCenter(of canvas: CanvasViewController) -> Card? {
        let center = canvas.camera.center
        return canvas.content.cards.values.min {
            ($0.frame.center - center).length < ($1.frame.center - center).length
        }
    }

    /// A composition with a selector and one workspace whose root canvas holds the D-56 content.
    private static func composition(
        of library: D56Library,
        window: InputTrackingWindow,
        in container: AppViewController
    ) async throws -> AppComposition {
        let clock = Fixtures.clock(device: library.device)
        let workspace = try Workspace(
            id: WorkspaceID(rawValue: library.canvas.rawValue),
            meta: RecordMeta(created: clock.now()),
            title: "D-56",
            sortKey: FractionalIndex(rawValue: "V")
        )
        try await library.repository.create(workspace)
        let composition = AppComposition(
            window: window,
            container: container,
            defaults: try XCTUnwrap(UserDefaults(suiteName: "OpenAnimationTests"))
        )
        composition.repository = library.repository
        composition.clock = clock
        composition.selector = WorkspaceSelectorModel(
            dependencies: WorkspaceSelectorModel.Dependencies(
                repository: library.repository,
                makeTimestamp: { clock.now() },
                makeWorkspaceID: { clock.makeIdentifier() },
                onSwitch: { [weak composition] in composition?.open($0) }
            )
        )
        return composition
    }

    /// The line of the report: the time, the frames, the late frames, and the largest jump.
    private static func reportLine(
        name: String,
        collector: FrameLoopCollector,
        cameras: [Camera],
        viewSize: Size,
        milliseconds: Double
    ) -> String {
        var report = FrameLoopReport()
        collector.fill(&report)
        let jump = largestJump(cameras, viewSize: viewSize)
        return String(
            format: "open of %@: %.0f ms to the child, %d frames, late %d, held %d, "
                + "largest move %.1f points, largest zoom step %.3f (late at %@)",
            name,
            milliseconds,
            report.frames,
            report.lateIntervals,
            heldFrames(cameras),
            jump.move,
            jump.zoom,
            latePlaces(report)
        ) + " " + startDetail(report)
    }

    /// The largest move of the screen center and the largest zoom ratio between two frames.
    private static func largestJump(_ cameras: [Camera], viewSize: Size) -> (
        move: Double, zoom: Double
    ) {
        var move = 0.0
        var zoom = 1.0
        for (before, after) in zip(cameras, cameras.dropFirst()) {
            let shift = (after.center - before.center).length * after.zoom
            move = max(move, shift)
            zoom = max(zoom, max(after.zoom / before.zoom, before.zoom / after.zoom))
        }
        return (move, zoom)
    }

    static func waitForCanvas(
        _ canvas: CanvasID,
        in composition: AppComposition
    ) async throws -> CanvasViewController {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            // A swap runs on after the container names the new canvas, and it refuses a leave.
            let isShown = !composition.container.isSwapping
            if isShown, let shown = composition.container.canvas, shown.canvasID == canvas {
                return shown
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw OpenTimedOut()
    }

    /// `true` after the first frame and the text and card layouts of a canvas.
    private static func isSettled(_ canvas: CanvasViewController) -> Bool {
        canvas.hasDrawnLoad && !canvas.renderer.isLoadingText && !canvas.renderer.isLoadingCards
    }

    static func waitForDrawn(_ canvas: CanvasViewController) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isSettled(canvas) {
            guard clock.now < deadline else { throw OpenTimedOut() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
