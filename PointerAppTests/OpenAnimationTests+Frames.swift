import Geometry
import XCTest

@testable import Rendering

/// The measures of the frames of a flight (m6-fix-plan.md task 2.1).
extension OpenAnimationTests {
    /// The report line of a leave, its late frames, and the held frames of the parent.
    struct LeaveMeasure {
        let text: String
        let late: Int
        let held: Int
    }

    /// The late frames of the child and the places of the late frames of the parent, for a
    /// report line: "(child late 1 of 8.3 20.1, parent late at 2:16.7)".
    static func lateDetail(child: FrameLoopReport, parent: FrameLoopReport) -> String {
        let childIntervals = child.intervals.map { String(format: "%.1f", $0) }
        return "(child late \(child.lateIntervals) of "
            + childIntervals.joined(separator: " ")
            + ", parent late at " + latePlaces(parent) + ")"
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
