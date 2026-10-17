import Foundation

/// The measurements of one frame-loop run (docs/m2-fix-plan.md, phase 0, task 3).
struct FrameLoopReport: CustomStringConvertible {
    /// A frame interval above this many milliseconds is late at 120 Hz.
    static let lateIntervalMilliseconds = 12.5

    /// The times between two presented frames, in milliseconds.
    var intervals: [Double] = []
    /// The main-thread time of the renderer in each display frame, in milliseconds.
    var mainThread: [Double] = []
    /// The render-thread time of each frame, in milliseconds.
    var renderThread: [Double] = []
    /// The GPU time of every second frame, in milliseconds.
    var gpu: [Double] = []
    /// The heap allocations of the process during each other frame.
    var allocations: [Double] = []
    /// The completed builds of the committed layer.
    var builds = 0
    /// The frames whose visible rectangle the front texture does not cover.
    var uncoveredFrames = 0
    /// The measured frames.
    var frames = 0

    /// The frames per second over the measured time.
    var frameRate: Double {
        let total = intervals.reduce(0, +)
        return total > 0 ? Double(intervals.count) * 1000 / total : 0
    }

    /// The intervals over `lateIntervalMilliseconds`.
    var lateIntervals: Int { intervals.filter { $0 > Self.lateIntervalMilliseconds }.count }

    var description: String {
        let rate = String(format: "%.1f fps", frameRate)
        return "\(rate), late \(lateIntervals)/\(intervals.count), builds \(builds), "
            + "uncovered \(uncoveredFrames)/\(frames); interval ms \(Self.summary(intervals)); "
            + "main ms \(Self.summary(mainThread)); "
            + "render ms \(Self.summary(renderThread)); GPU ms \(Self.summary(gpu)); "
            + "allocations \(Self.summary(allocations))"
    }

    /// Returns the mean, the median, the 99th percentile, and the largest value.
    static func summary(_ values: [Double]) -> String {
        guard !values.isEmpty else { return "none" }
        let sorted = values.sorted()
        let mean = sorted.reduce(0, +) / Double(sorted.count)
        let median = sorted[sorted.count / 2]
        let high = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.99))]
        return String(
            format: "mean %.2f p50 %.2f p99 %.2f max %.2f",
            mean,
            median,
            high,
            sorted[sorted.count - 1]
        )
    }
}
