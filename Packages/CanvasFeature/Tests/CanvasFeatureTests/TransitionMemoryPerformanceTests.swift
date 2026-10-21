import XCTest

/// The memory peak of an open from the D-56 canvas into a D-56 child and of the leave back
/// (m6-plan.md task 3.6, D-110). At the start of the open, the parent keeps a frozen copy of its
/// frame and frees its committed textures and its eraser mask. The simulator skips the test.
@MainActor
final class TransitionMemoryPerformanceTests: XCTestCase {
    /// The budgets of D-110 on the iPad Pro 11-inch (M4), in MB: the largest of 3 runs alone on
    /// 2026-10-21 plus about 8 %, as D-93 did. The open peaked at 610 to 619 MB, the leave at 887
    /// to 898 MB (m6-plan.md section 6.3).
    private static let openBudgetMegabytes = 670.0
    private static let leaveBudgetMegabytes = 970.0

    func testMemoryPeakOfAnOpenAndALeaveBetweenD56Canvases() async throws {
        let host = try OnScreenCanvas.host()
        let library = try await D56Library.make()
        defer { library.remove() }
        let measure = try await OnScreenCanvas.transition(library, in: host)
        let line = String(
            format: "transition memory: parent held %.0f MB, open peak %.0f MB, leave peak %.0f MB",
            measure.parentHeldMegabytes,
            measure.openPeakMegabytes,
            measure.leavePeakMegabytes
        )
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(measure.openPeakMegabytes, Self.openBudgetMegabytes, line)
        XCTAssertLessThanOrEqual(measure.leavePeakMegabytes, Self.leaveBudgetMegabytes, line)
    }
}
