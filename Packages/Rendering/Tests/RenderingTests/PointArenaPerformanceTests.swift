import Metal
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The upload of a full canvas into the point arena (the M2 fix plan, phase 4, task 3). The
/// times are valid on a device only, so they run on the iPad only (D-77).
///
/// Each test runs its loop in 3 rounds, each with a new arena, and reports the median of the
/// slowest call of a round (D-177 point 1). A stall of the thread from outside the code, 1.4 ms
/// once in 96 runs, then changes one round only (the M10 plan section 6.44).
@MainActor
final class PointArenaPerformanceTests: XCTestCase {
    /// The longest time of one upload, with a growth of the arena, in milliseconds.
    private static let maxUploadMilliseconds = 1.0
    /// The longest time of one upload with an eviction, in milliseconds.
    private static let maxEvictionMilliseconds = 0.5
    /// The rounds of each loop. The sample is the median of their slowest call.
    private static let rounds = 3

    func testUploadOfTwoHundredThousandHandwritingStrokes() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let strokes = PerformanceContent.handwriting(count: 200_000)
        var rounds: [(slowest: Double, line: String)] = []
        for _ in 0..<Self.rounds {
            try autoreleasepool {
                rounds.append(try Self.uploadRound(device: device, strokes: strokes))
            }
        }
        let slowest = try XCTUnwrap(PerformanceRecord.median(rounds.map(\.slowest)))
        let line =
            String(format: "upload: slowest %.3f ms, median of %d rounds; ", slowest, Self.rounds)
            + rounds.map(\.line).joined(separator: "; ")
        PerformanceRecord.attach(["upload.slowest.ms": slowest], line: line)
        XCTAssertLessThanOrEqual(slowest, Self.maxUploadMilliseconds, line)
    }

    /// Uploads `strokes` into a new arena, and returns the slowest upload in milliseconds.
    private static func uploadRound(
        device: any MTLDevice,
        strokes: [Stroke]
    ) throws -> (slowest: Double, line: String) {
        let configuration = RendererConfiguration()
        let arena = try PointArena(
            device: device,
            initialSlabs: configuration.initialArenaSlabs,
            byteBudget: configuration.arenaByteBudget
        )
        let store = StrokeStore(arena: arena)
        let slots = strokes.map { store.add($0) }
        var slowest = 0.0
        var slowestGrowth = 0.0
        var largestFootprint = 0
        for slot in slots {
            let buffers = arena.buffers.count
            let start = CACurrentMediaTime()
            _ = store.makeResident(slot, frame: 1)
            let time = (CACurrentMediaTime() - start) * 1000
            slowest = max(slowest, time)
            if arena.buffers.count > buffers { slowestGrowth = max(slowestGrowth, time) }
            largestFootprint = max(largestFootprint, arena.footprint)
        }
        let line = String(
            format: "slowest %.3f ms, slowest growth %.3f ms, %d buffers, %d MB",
            slowest,
            slowestGrowth,
            arena.buffers.count,
            largestFootprint >> 20
        )
        XCTAssertLessThanOrEqual(
            largestFootprint,
            configuration.arenaByteBudget + PointArena.bytesPerBuffer,
            line
        )
        return (slowest, line)
    }

    func testEvictionWithSixteenMegabyteArena() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let strokes = PerformanceContent.handwriting(count: 200_000)
        var rounds: [(slowest: Double, line: String)] = []
        for _ in 0..<Self.rounds {
            try autoreleasepool {
                rounds.append(try Self.evictionRound(device: device, strokes: strokes))
            }
        }
        let slowest = try XCTUnwrap(PerformanceRecord.median(rounds.map(\.slowest)))
        let line =
            String(format: "eviction: slowest %.3f ms, median of %d rounds; ", slowest, Self.rounds)
            + rounds.map(\.line).joined(separator: "; ")
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["eviction.slowest.ms": slowest])
        XCTAssertLessThan(slowest, Self.maxEvictionMilliseconds, line)
    }

    /// Draws `strokes` through an arena of one buffer, 1,000 strokes per frame, and returns the
    /// slowest upload with its evictions in milliseconds.
    private static func evictionRound(
        device: any MTLDevice,
        strokes: [Stroke]
    ) throws -> (slowest: Double, line: String) {
        let arena = try PointArena(
            device: device,
            initialSlabs: 1,
            byteBudget: PointArena.bytesPerBuffer
        )
        let store = StrokeStore(arena: arena)
        let slots = strokes.map { store.add($0) }
        var slowest = 0.0
        var missing = 0
        // Each frame draws 1,000 strokes, so the arena of 16 MB evicts in most frames.
        for (index, slot) in slots.enumerated() {
            let frame = UInt64(index / 1_000 + 1)
            let start = CACurrentMediaTime()
            if store.makeResident(slot, frame: frame) == nil { missing += 1 }
            slowest = max(slowest, (CACurrentMediaTime() - start) * 1000)
        }
        let line = String(
            format: "slowest %.3f ms, %d strokes not drawn, %d MB",
            slowest,
            missing,
            arena.footprint >> 20
        )
        XCTAssertEqual(missing, 0, line)
        return (slowest, line)
    }
}
