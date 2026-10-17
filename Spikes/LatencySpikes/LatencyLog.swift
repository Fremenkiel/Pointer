import Foundation
import QuartzCore

/// One presented frame of the custom spike that contains new pencil samples.
/// All times are seconds on the `CACurrentMediaTime()` clock, if the clock test passes.
struct FrameRecord {
    /// `UITouch.timestamp` of the newest real (not predicted) sample in the frame.
    var newestSampleTime: Double
    /// `CACurrentMediaTime()` at the entry of the first touch handler that fed this frame.
    var firstEventTime: Double
    /// `CACurrentMediaTime()` before `nextDrawable()`.
    var renderStart: Double
    /// `CACurrentMediaTime()` after `nextDrawable()` returned.
    var drawableAcquired: Double
    /// `CACurrentMediaTime()` after `endEncoding()`.
    var encodeEnd: Double
    /// `CACurrentMediaTime()` after the present and commit calls returned.
    var submitEnd: Double
    /// `MTLDrawable.presentedTime`. Zero if the drawable was not presented.
    var presentedTime: Double = 0
    /// `CACurrentMediaTime()` when the presented handler ran.
    var presentedHandlerTime: Double = 0
    /// `UIUpdateInfo.estimatedPresentationTime` of the update that drew the frame.
    var estimatedPresentationTime: Double
    var lowLatencyConfirmed: Bool
    var immediatePresentationExpected: Bool
    var performingLowLatencyPhases: Bool

    /// Software latency: newest sample to glass.
    var latency: Double { presentedTime - newestSampleTime }
    /// CPU time from the pencil event to the end of command encoding (review A-15).
    var cpuTime: Double { encodeEnd - firstEventTime }
}

/// One clock test pair: an event timestamp and `CACurrentMediaTime()` when the app saw it.
struct ClockPair {
    var eventTime: Double
    var now: Double
}

/// One handoff of the hybrid spike.
struct HandoffRecord {
    var drawingChangedTime: Double
    var metalPresentedTime: Double = 0
    var zoom: Double
    var toolWidth: Double
    var meanPencilKitPointWidth: Double
    var maxDifference: Int = -1
    var differingPixels: Int = 0
    var comparedPixels: Int = 0
    var inkRatio: Double = 0
}

/// Collects the measurements of one configuration and writes them as CSV into Documents.
final class LatencyLog {
    private(set) var frames: [FrameRecord] = []
    private(set) var touchClock: [ClockPair] = []
    private(set) var handoffs: [HandoffRecord] = []
    var droppedDrawables = 0
    /// Diagnostic counters: all touch events, accepted pencil events, update link calls, frames drawn.
    var touchEvents = 0
    var acceptedEvents = 0
    var linkCalls = 0
    var framesDrawn = 0
    var lastTouchType = "none"

    func add(_ frame: FrameRecord) { frames.append(frame) }
    func addTouchClock(_ pair: ClockPair) { if touchClock.count < 10_000 { touchClock.append(pair) } }
    func addHandoff(_ record: HandoffRecord) -> Int {
        handoffs.append(record)
        return handoffs.count - 1
    }
    func updateHandoff(_ index: Int, _ change: (inout HandoffRecord) -> Void) { change(&handoffs[index]) }

    func reset() {
        frames.removeAll()
        touchClock.removeAll()
        handoffs.removeAll()
        droppedDrawables = 0
    }

    /// A short text for the screen.
    func summary(title: String) -> String {
        var lines = [title]
        lines.append("touches \(touchEvents) (last type \(lastTouchType))  accepted \(acceptedEvents)  link calls \(linkCalls)  frames drawn \(framesDrawn)")
        let presented = frames.filter { $0.presentedTime > 0 }
        if !presented.isEmpty {
            let latency = Stats(presented.map { $0.latency * 1000 })
            let cpu = Stats(frames.map { $0.cpuTime * 1000 })
            let wait = Stats(frames.map { ($0.drawableAcquired - $0.renderStart) * 1000 })
            let over = frames.filter { $0.cpuTime > 0.003 }.count
            let lowLatency = frames.filter { $0.performingLowLatencyPhases }.count
            let immediate = frames.filter { $0.immediatePresentationExpected }.count
            lines.append("frames \(frames.count)  presented \(presented.count)  not presented \(frames.count - presented.count)  no drawable \(droppedDrawables)")
            lines.append("latency ms   \(latency.text)")
            lines.append("cpu ms       \(cpu.text)  over 3 ms: \(over)")
            lines.append("drawable ms  \(wait.text)")
            lines.append("low-latency phases \(lowLatency)/\(frames.count)  immediate expected \(immediate)/\(frames.count)")
            let presentDelta = Stats(presented.map { ($0.presentedHandlerTime - $0.presentedTime) * 1000 })
            let estimateDelta = Stats(presented.map { ($0.presentedTime - $0.estimatedPresentationTime) * 1000 })
            lines.append("clock: handler-presented ms \(presentDelta.text)")
            lines.append("clock: presented-estimated ms \(estimateDelta.text)")
        }
        if !touchClock.isEmpty {
            let delta = Stats(touchClock.map { ($0.now - $0.eventTime) * 1000 })
            lines.append("clock: now-touch ms \(delta.text)")
        }
        if !handoffs.isEmpty {
            let done = handoffs.filter { $0.maxDifference >= 0 }
            let gap = Stats(handoffs.filter { $0.metalPresentedTime > 0 }.map { ($0.metalPresentedTime - $0.drawingChangedTime) * 1000 })
            lines.append("handoffs \(handoffs.count)  change to metal ms \(gap.text)")
            if let last = done.last {
                let percent = Double(last.differingPixels) / Double(max(last.comparedPixels, 1)) * 100
                lines.append(String(format: "last handoff: max diff %d/255, pixels > 25%%: %d (%.2f%%), ink metal/pk %.3f, pk width %.2f, tool width %.2f",
                                    last.maxDifference, last.differingPixels, percent, last.inkRatio,
                                    last.meanPencilKitPointWidth, last.toolWidth))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Writes the records as CSV files and returns the folder.
    @discardableResult
    func write(name: String) -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = documents.appendingPathComponent("\(stamp) \(name)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var frameCSV = "newestSample,firstEvent,renderStart,drawableAcquired,encodeEnd,submitEnd,presented,presentedHandler,estimatedPresentation,lowLatencyConfirmed,immediateExpected,lowLatencyPhases,latencyMs,cpuMs\n"
        for f in frames {
            frameCSV += [f.newestSampleTime, f.firstEventTime, f.renderStart, f.drawableAcquired, f.encodeEnd,
                         f.submitEnd, f.presentedTime, f.presentedHandlerTime, f.estimatedPresentationTime]
                .map { String(format: "%.6f", $0) }.joined(separator: ",")
            frameCSV += ",\(f.lowLatencyConfirmed),\(f.immediatePresentationExpected),\(f.performingLowLatencyPhases)"
            frameCSV += String(format: ",%.3f,%.3f\n", f.latency * 1000, f.cpuTime * 1000)
        }
        var clockCSV = "touchTimestamp,mediaTimeAtHandler\n"
        for c in touchClock { clockCSV += String(format: "%.6f,%.6f\n", c.eventTime, c.now) }
        var handoffCSV = "drawingChanged,metalPresented,zoom,toolWidth,pkPointWidth,maxDiff,differingPixels,comparedPixels,inkRatio\n"
        for h in handoffs {
            handoffCSV += String(format: "%.6f,%.6f,%.3f,%.3f,%.3f,%d,%d,%d,%.4f\n",
                                 h.drawingChangedTime, h.metalPresentedTime, h.zoom, h.toolWidth,
                                 h.meanPencilKitPointWidth, h.maxDifference, h.differingPixels,
                                 h.comparedPixels, h.inkRatio)
        }
        try? frameCSV.write(to: folder.appendingPathComponent("frames.csv"), atomically: true, encoding: .utf8)
        try? clockCSV.write(to: folder.appendingPathComponent("clock.csv"), atomically: true, encoding: .utf8)
        try? handoffCSV.write(to: folder.appendingPathComponent("handoffs.csv"), atomically: true, encoding: .utf8)
        try? summary(title: name).write(to: folder.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        return folder
    }
}

/// Median, 95th percentile, and maximum.
struct Stats {
    let median: Double
    let p95: Double
    let max: Double

    init(_ values: [Double]) {
        let sorted = values.sorted()
        guard !sorted.isEmpty else {
            median = 0
            p95 = 0
            max = 0
            return
        }
        median = sorted[sorted.count / 2]
        p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        max = sorted[sorted.count - 1]
    }

    var text: String { String(format: "med %.2f  p95 %.2f  max %.2f", median, p95, max) }
}
