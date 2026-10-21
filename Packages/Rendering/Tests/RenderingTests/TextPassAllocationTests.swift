import Geometry
import Metal
import Model
import XCTest

@testable import Rendering

/// The heap allocations of a text pass with cached glyphs, against a bare render pass with one
/// draw (PERF-01, D-43, task 2.2 of docs/m5-plan.md).
@MainActor
final class TextPassAllocationTests: XCTestCase {
    /// A text encoder with one box of 200 characters, and a target at zoom 1.
    private struct Rig {
        let encoder: TextEncoder
        let target: InkTarget
        let ids: [GreenItem]
        let resources: InkResources
    }

    private static func rig() throws -> Rig {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        let store = TextStore()
        let creator = DeviceID(rawValue: UUID())
        let box = try TextBox(
            id: TextBoxID(rawValue: UUID()),
            meta: RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: creator)),
            canvasID: CanvasID(rawValue: UUID()),
            origin: Point(x: -100, y: -40),
            text: String(repeating: "node ", count: 40),
            sortKey: FractionalIndex(rawValue: "V")
        )
        store.add(box)
        let encoder = TextEncoder(
            resources: resources,
            store: store,
            atlas: GlyphAtlas(device: device, byteBudget: 16 << 20),
            ring: try GlyphRing(device: device, capacity: 4_096)
        )
        let texture = try resources.makeTarget(
            width: 800,
            height: 600,
            format: InkResources.committedFormat
        )
        let target = InkTarget(
            texture: texture,
            camera: Camera(center: .zero, zoom: 1),
            displayScale: 2
        )
        return Rig(encoder: encoder, target: target, ids: [.textBox(box.id)], resources: resources)
    }

    func testTextPassWithCachedGlyphsAllocatesNoMoreThanBarePass() throws {
        let rig = try Self.rig()
        let (encoder, target, ids, resources) = (rig.encoder, rig.target, rig.ids, rig.resources)
        let texture = target.texture
        var ours: [Int] = []
        var bare: [Int] = []
        for frame in 1...20 {
            let buffer = try XCTUnwrap(resources.queue.makeCommandBuffer())
            let context = FrameContext(commandBuffer: buffer, frame: UInt64(frame))
            encoder.beginFrame()
            let count = AllocationCounter.countMainThread {
                _ = encoder.encodePass(
                    context,
                    target: target,
                    ids: ids,
                    cursor: 0,
                    options: TextEncoder.Options()
                )
            }
            // The first frame draws the glyphs into the atlas.
            if frame > 1, let count { ours.append(count) }
            buffer.commit()
            buffer.waitUntilCompleted()
            let other = try XCTUnwrap(resources.queue.makeCommandBuffer())
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .load
            let bareCount = AllocationCounter.countMainThread {
                guard let made = other.makeRenderCommandEncoder(descriptor: pass) else { return }
                made.setRenderPipelineState(resources.glyphPipeline)
                made.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                made.endEncoding()
            }
            if let bareCount { bare.append(bareCount) }
            other.commit()
            other.waitUntilCompleted()
        }
        let median = { (values: [Int]) in values.sorted()[values.count / 2] }
        let line = "text pass allocations p50 \(median(ours)), bare pass p50 \(median(bare))"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(median(ours), median(bare), line)
    }
}
