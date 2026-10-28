import Geometry
import XCTest

@testable import Rendering

/// The measures of the frames of a flight (the M6 fix plan task 2.1).
extension OpenAnimationTests {
    /// The report line of a leave, its late frames, and the held frames of the parent.
    struct LeaveMeasure {
        let text: String
        let late: Int
        let held: Int
    }

    /// The late and the held frames of a flight as samples, which the compare records without a
    /// gate (D-172, D-177).
    static func flightSamples(_ flight: String, late: Int, held: Int) -> [String: Double] {
        ["\(flight)-late.count": Double(late), "\(flight)-held.count": Double(held)]
    }

    /// The late frames of the child and the places of the late frames of the parent, for a
    /// report line: "(child late 1 of 8.3 20.1, parent late at 2:16.7)".
    static func lateDetail(child: FrameLoopReport, parent: FrameLoopReport) -> String {
        let childIntervals = child.intervals.map { String(format: "%.1f", $0) }
        return "(child late \(child.lateIntervals) of "
            + childIntervals.joined(separator: " ")
            + ", parent late at " + latePlaces(parent) + "; " + startDetail(parent) + ")"
            + " " + lateNeighborhood(parent)
    }

    /// The first frames of a report (D-136): the target and the presented times in
    /// milliseconds after the first target, the render-thread times, and the frames that never
    /// showed.
    static func startDetail(_ report: FrameLoopReport) -> String {
        let count = 5
        guard let first = report.targetTimes.first else { return "no frames" }
        let format = { (values: [Double]) in
            values.prefix(count).map { String(format: "%.1f", ($0 - first) * 1000) }
                .joined(separator: " ")
        }
        let render = report.renderThread.prefix(count).map { String(format: "%.2f", $0) }
        let gpu = report.gpuSpans.filter { $0.end >= first }.prefix(count).map {
            String(format: "%.1f-%.1f", ($0.start - first) * 1000, ($0.end - first) * 1000)
        }
        return "targets " + format(report.targetTimes) + ", presented "
            + format(report.presentedTimes) + ", render ms " + render.joined(separator: " ")
            + ", GPU " + gpu.joined(separator: " ") + ", dropped \(report.droppedFrames)"
    }

    /// The frames around each late interval (the M10 plan task 5.1): for frames two before to two
    /// after, the target and the presented time in milliseconds after the first target, the
    /// render-thread time, and the GPU spans that start near the target.
    static func lateNeighborhood(_ report: FrameLoopReport) -> String {
        guard let first = report.targetTimes.first else { return "" }
        let late = FrameLoopReport.lateIntervalMilliseconds
        let ms = { (time: Double) in String(format: "%.1f", (time - first) * 1000) }
        var parts: [String] = []
        for place in report.intervals.indices where report.intervals[place] > late {
            let frames = max(0, place - 2)...min(report.presentedTimes.count - 1, place + 2)
            let lines = frames.map { index -> String in
                let target =
                    report.targetTimes.indices.contains(index)
                    ? ms(report.targetTimes[index]) : "-"
                let render =
                    report.renderThread.indices.contains(index)
                    ? String(format: "%.2f", report.renderThread[index]) : "-"
                let near =
                    report.targetTimes.indices.contains(index)
                    ? report.gpuSpans.filter {
                        abs($0.start - report.targetTimes[index]) < 0.006
                    }.map { ms($0.start) + "-" + ms($0.end) }.joined(separator: "/") : ""
                return "\(index): t \(target) p \(ms(report.presentedTimes[index])) r \(render)"
                    + (near.isEmpty ? "" : " g \(near)")
            }
            parts.append("[" + lines.joined(separator: "; ") + "]")
        }
        return parts.joined(separator: " ")
    }

    /// The places and the lengths of the late intervals of a report: "2:16.7 9:25.0".
    static func latePlaces(_ report: FrameLoopReport) -> String {
        let late = FrameLoopReport.lateIntervalMilliseconds
        return report.intervals.indices.filter { report.intervals[$0] > late }
            .map { String(format: "%d:%.1f", $0, report.intervals[$0]) }
            .joined(separator: " ")
    }

    /// The frames of a flight that repeat the camera of the frame before: the screen holds while
    /// the camera must move, and then jumps. The frames before the first move and the frames at
    /// the last camera do not count.
    static func heldFrames(_ cameras: [Camera]) -> Int {
        guard let first = cameras.first, let last = cameras.last,
            let moving = cameras.firstIndex(where: { $0 != first })
        else { return 0 }
        let flight = cameras[moving...]
        return zip(flight.dropFirst(), flight).filter { $0 == $1 && $0 != last }.count
    }
}
