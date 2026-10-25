import XCTest

/// M3 acceptance 3: a canvas with the content of D-56 opens to the first frame in under 300 ms
/// on the device (architecture.md section 12, PERF-03). The test opens the canvas on the screen
/// with its render thread, as the app does. The simulator skips it.
@MainActor
final class CanvasOpenPerformanceTests: XCTestCase {
    /// The budget of architecture.md section 12, in milliseconds.
    private static let budgetMilliseconds = 300.0
    /// The opens of the measurement.
    private static let openCount = 10

    func testOpenOfTwentyThousandStrokesAndTenThousandNodes() async throws {
        let host = try OnScreenCanvas.host()
        let library = try await D56Library.make()
        defer { await library.remove() }
        var times: [Double] = []
        for _ in 0..<Self.openCount {
            let open = try await OnScreenCanvas.open(library, in: host)
            let line = String(
                format: "load %.1f ms, total %.1f ms",
                open.loadMilliseconds,
                open.totalMilliseconds
            )
            XCTContext.runActivity(named: line) { _ in }
            times.append(open.totalMilliseconds)
        }
        times.sort()
        let line = String(
            format: "open to the first frame: median %.1f ms, slowest %.1f ms over %d opens",
            times[times.count / 2],
            times.last ?? 0,
            times.count
        )
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach([
            "open.median.ms": times[times.count / 2],
            "open.slowest.ms": times.last ?? 0,
        ])
        XCTAssertLessThanOrEqual(times.last ?? .infinity, Self.budgetMilliseconds, line)
    }
}
