import XCTest

/// A canvas with the content of D-56 takes under 300 MB on the device (architecture.md section
/// 12, PERF-03). The test reads the growth of the process memory from the start of the load to
/// the first frame with all strokes, and the peak on the way. The simulator skips it.
///
/// The test makes one open. A closed canvas gives its memory back to the allocator of the
/// process, not to the system, so a second open reuses it and shows too little growth.
@MainActor
final class CanvasMemoryPerformanceTests: XCTestCase {
    /// The budget of architecture.md section 12, in MB.
    private static let budgetMegabytes = 300.0

    func testMemoryOfTwentyThousandStrokesAndTenThousandNodes() async throws {
        let host = try OnScreenCanvas.host()
        let library = try await D56Library.make()
        defer { library.remove() }
        let open = try await OnScreenCanvas.open(library, in: host)
        let line = String(
            format: "memory of the open canvas: held %.0f MB, peak %.0f MB",
            open.heldMegabytes,
            open.peakMegabytes
        )
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(open.peakMegabytes, Self.budgetMegabytes, line)
    }
}
