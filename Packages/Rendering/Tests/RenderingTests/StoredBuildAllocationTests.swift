import Geometry
import Metal
import Model
import Testing

@testable import Rendering

/// The heap allocations of a text pass that builds a stored run (PERF-01). An allocation suite:
/// it never runs under Metal validation, which allocates in each pass (D-186).
@MainActor
@Suite("Stored build allocations")
struct StoredBuildAllocationTests {
    @Test("A pass that builds a run allocates nothing in Pointer code (PERF-01)")
    func buildAllocatesNothing() throws {
        let rig = try StoredGlyphTests.rig(isStored: true)
        try StoredGlyphTests.draw(rig, frame: 1)
        try StoredGlyphTests.draw(rig, frame: 2)
        #expect(rig.encoder.stored?.runs.runs.count == StoredGlyphTests.texts.count)
        var counts: [Int] = []
        var callers: [String] = []
        for frame in 3..<23 {
            // A new text gives the box a new layout version, so the pass builds its run again.
            let text = StoredGlyphTests.texts[0] + String(repeating: "x", count: frame)
            _ = rig.store.add(
                try StoredGlyphTests.box(text, index: 0, origin: Point(x: -180, y: -90))
            )
            let buffer = try #require(rig.resources.queue.makeCommandBuffer())
            rig.encoder.beginFrame()
            // The review of 2026-10-28 (3.3.1, 3.3.2) read two list copies and a resource list
            // per build. The tracer shows no Pointer allocation, before and after a change of
            // both, and the system makes two (D-43).
            let result = AllocationTracer.trace {
                _ = rig.encoder.encodePass(
                    FrameContext(commandBuffer: buffer, frame: UInt64(frame)),
                    target: rig.target,
                    ids: rig.ids,
                    cursor: 0,
                    options: TextEncoder.Options()
                )
            }
            buffer.commit()
            buffer.waitUntilCompleted()
            if let result {
                counts.append(result.pointer)
                callers = result.pointerCallers
            }
        }
        let median = counts.sorted()[counts.count / 2]
        #expect(median == 0, "A pass with a build allocated \(median) times: \(counts) \(callers)")
    }

}
