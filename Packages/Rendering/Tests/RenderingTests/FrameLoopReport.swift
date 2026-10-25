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
    /// The presented times of the shown frames, in seconds, sorted.
    var presentedTimes: [Double] = []
    /// The target times of the rendered frames, in seconds, in the order of the frames.
    var targetTimes: [Double] = []
    /// The frames that the display never showed: a presented time of 0.
    var droppedFrames = 0
    /// The GPU start and end times of the measured frames, in seconds, sorted by the start.
    var gpuSpans: [(start: Double, end: Double)] = []

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

    /// The samples of the run for the baseline compare (D-172, D-177). Late frames and uncovered
    /// frames are counts, which the compare records without a gate.
    var samples: [String: Double] {
        [
            "main.p99.ms": Self.percentile(mainThread, 0.99),
            "render.p50.ms": Self.percentile(renderThread, 0.5),
            "render.p99.ms": Self.percentile(renderThread, 0.99),
            "gpu.p50.ms": Self.percentile(gpu, 0.5),
            "gpu.p99.ms": Self.percentile(gpu, 0.99),
            "late.count": Double(lateIntervals),
            "uncovered.count": Double(uncoveredFrames),
        ]
    }

    /// Returns the value at `fraction` of the sorted values, as `summary` takes it, or 0.
    static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
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
