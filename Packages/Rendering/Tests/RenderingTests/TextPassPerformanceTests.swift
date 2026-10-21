import Geometry
import Metal
import Model
import QuartzCore
import XCTest

@testable import Rendering

/// The CPU time of the text pass over the 300 boxes of D-56 that one committed texture holds at
/// zoom 1, with cached glyphs (PERF-03, D-94, review of M5). The review measured 29 ns per glyph
/// before the pass kept its loop state in local values, and 17 ns after it: 1.39 ms and 0.83 ms.
@MainActor
final class TextPassPerformanceTests: XCTestCase {
    /// The budget: the measured 0.83 ms plus about 30 % for the spread of device runs.
    private static let budgetMilliseconds = 1.1
    /// The texture of a build on the iPad Pro 11-inch (M4), with its margin.
    private static let targetSize = (width: 3_340, height: 2_500)

    /// The encoder over the text of D-56, a target at zoom 1, and the boxes in the target.
    private struct Rig {
        let encoder: TextEncoder
        let target: InkTarget
        let ids: [TextBoxID]
        let resources: InkResources
    }

    private static func rig() throws -> Rig {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        let store = TextStore()
        for box in try PerformanceContent.textBoxes(count: 5_000) {
            store.add(box)
        }
        let encoder = TextEncoder(
            resources: resources,
            store: store,
            atlas: GlyphAtlas(device: device, byteBudget: 16 << 20),
            ring: try GlyphRing(device: device, capacity: 65_536)
        )
        let target = InkTarget(
            texture: try resources.makeTarget(
                width: targetSize.width,
                height: targetSize.height,
                format: InkResources.committedFormat
            ),
            camera: Camera(center: .zero, zoom: 1),
            displayScale: 2
        )
        var ids: [TextBoxID] = []
        store.grid.forEachItem(touching: target.canvasRect) { ids.append($0) }
        return Rig(encoder: encoder, target: target, ids: ids, resources: resources)
    }

    func testTextPassOfD56AtZoomOne() throws {
        let rig = try Self.rig()
        let (encoder, target, ids, resources) = (rig.encoder, rig.target, rig.ids, rig.resources)
        var times: [Double] = []
        for frame in 1...12 {
            let buffer = try XCTUnwrap(resources.queue.makeCommandBuffer())
            let context = FrameContext(commandBuffer: buffer, frame: UInt64(frame))
            encoder.beginFrame()
            let start = CACurrentMediaTime()
            let cursor = encoder.encodePass(
                context,
                target: target,
                ids: ids,
                cursor: 0,
                options: TextEncoder.Options()
            )
            // The first frames draw the glyphs into the atlas.
            if frame > 2 { times.append((CACurrentMediaTime() - start) * 1_000) }
            XCTAssertEqual(cursor, ids.count, "One pass holds the boxes of zoom 1")
            buffer.commit()
            buffer.waitUntilCompleted()
        }
        let median = times.sorted()[times.count / 2]
        let glyphs = encoder.ring.used
        let line = String(
            format: "text pass of %d boxes, %d glyphs: median %.3f ms, %.1f ns per glyph",
            ids.count,
            glyphs,
            median,
            median * 1e6 / Double(max(glyphs, 1))
        )
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThan(median, Self.budgetMilliseconds, line)
    }
}
