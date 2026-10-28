import Geometry
import Model
import QuartzCore
import XCTest

@testable import CanvasFeature
@testable import Pointer
@testable import Rendering

/// The child canvas of an open, which loads and draws its first frames during the flight of the
/// parent (the M10 plan task 5.1).
extension OpenAnimationTests {
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
        // The child canvas and its first frames run during the flight (the M10 plan task 5.1).
        let childCollector = FrameLoopCollector(viewSize: viewSize)
        childCollector.measure(from: start, to: start + 5)
        let watch = Task { @MainActor in
            await watchChild(card.childCanvasID, in: composition, collector: childCollector)
        }
        composition.openChild(card)
        let child = try await waitForCanvas(card.childCanvasID, in: composition)
        let end = CACurrentMediaTime()
        watch.cancel()
        let times = await watch.value
        let line =
            reportLine(
                name: name,
                collector: collector,
                cameras: cameras.all,
                viewSize: viewSize,
                milliseconds: (end - start) * 1000
            ) + " " + childDetail(times, collector: childCollector, parent: collector)
        var report = FrameLoopReport()
        collector.fill(&report)
        return Measure(
            text: line,
            late: report.lateIntervals,
            held: heldFrames(cameras.all),
            child: child
        )
    }

    /// The times when the child canvas came and when the swap to it started.
    struct ChildTimes {
        var added: Double?
        var swapStarted: Double?
    }

    /// Waits for the child canvas of an open in the container, notes the time when it comes,
    /// watches its frames with `collector`, and notes the time when the swap to it starts.
    static func watchChild(
        _ canvas: CanvasID,
        in composition: AppComposition,
        collector: FrameLoopCollector
    ) async -> ChildTimes {
        var times = ChildTimes()
        for _ in 0..<5_000 where !Task.isCancelled && times.swapStarted == nil {
            let child = composition.container.children
                .compactMap { $0 as? CanvasViewController }
                .first { $0.canvasID == canvas }
            if times.added == nil, let child {
                times.added = CACurrentMediaTime()
                child.renderer.engine.post { $0.observer = collector }
            }
            if composition.container.isSwapping { times.swapStarted = CACurrentMediaTime() }
            do {
                try await Task.sleep(for: .milliseconds(1))
            } catch {
                return times
            }
        }
        return times
    }

    /// The time when the child came and its first presented frames, in milliseconds after the
    /// first target of the parent.
    static func childDetail(
        _ times: ChildTimes,
        collector: FrameLoopCollector,
        parent: FrameLoopCollector
    ) -> String {
        var report = FrameLoopReport()
        parent.fill(&report)
        var childReport = FrameLoopReport()
        collector.fill(&childReport)
        guard let first = report.targetTimes.first else { return "" }
        let ms = { (time: Double) in String(format: "%.1f", (time - first) * 1000) }
        let presents = childReport.presentedTimes.prefix(5).map(ms).joined(separator: " ")
        return "child added " + (times.added.map(ms) ?? "-") + ", swap started "
            + (times.swapStarted.map(ms) ?? "-") + ", child presented " + presents
    }
}
