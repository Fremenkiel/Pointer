import Metal
import QuartzCore
import XCTest

@testable import Rendering

/// The upload of a full canvas into the point arena (docs/m2-fix-plan.md, phase 4, task 3). The
/// times are valid on a device only, so the simulator skips these tests.
@MainActor
final class PointArenaPerformanceTests: XCTestCase {
    /// The longest time of one upload, with a growth of the arena, in milliseconds.
    private static let maxUploadMilliseconds = 1.0

    func testUploadOfTwoHundredThousandHandwritingStrokes() throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Upload times are valid on a device only.")
        #else
            let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
            let configuration = RendererConfiguration()
            let arena = try PointArena(
                device: device,
                initialSlabs: configuration.initialArenaSlabs,
                byteBudget: configuration.arenaByteBudget
            )
            let store = StrokeStore(arena: arena)
            let slots = PerformanceContent.handwriting(count: 200_000).map { store.add($0) }
            var slowest = 0.0
            var slowestGrowth = 0.0
            var largestFootprint = 0
            for slot in slots {
                let buffers = arena.buffers.count
                let start = CACurrentMediaTime()
                _ = store.residentInfo(of: slot, frame: 1)
                let time = (CACurrentMediaTime() - start) * 1000
                slowest = max(slowest, time)
                if arena.buffers.count > buffers { slowestGrowth = max(slowestGrowth, time) }
                largestFootprint = max(largestFootprint, arena.footprint)
            }
            let line = String(
                format: "upload: slowest %.3f ms, slowest growth %.3f ms, %d buffers, %d MB",
                slowest,
                slowestGrowth,
                arena.buffers.count,
                largestFootprint >> 20
            )
            XCTContext.runActivity(named: line) { _ in }
            XCTAssertLessThanOrEqual(slowest, Self.maxUploadMilliseconds, line)
            XCTAssertLessThanOrEqual(
                largestFootprint,
                configuration.arenaByteBudget + PointArena.bytesPerBuffer,
                line
            )
        #endif
    }
}
