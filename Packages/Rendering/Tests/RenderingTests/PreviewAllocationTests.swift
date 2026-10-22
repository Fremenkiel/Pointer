import Geometry
import Metal
import Model
import XCTest

@testable import Rendering

/// The heap allocations of a green pass with 10 cards whose previews are in the atlas, against a
/// bare render pass with the same draws (PERF-01, D-43, m6-plan.md task 3.3).
@MainActor
final class PreviewAllocationTests: XCTestCase {
    private struct Rig {
        let encoder: TextEncoder
        let target: InkTarget
        let ids: [GreenItem]
        let resources: InkResources
        let atlas: PreviewAtlas
    }

    /// 10 cards in a row, each with a title.
    private static func cards() throws -> [Card] {
        try (0..<10).map { index in
            let frame = Rect(
                origin: Point(x: -300 + Double(index) * 60, y: -30),
                size: Size(width: 64, height: 48)
            )
            return try CardStoreTests.card(UInt8(index + 1), frame: frame, title: "Card \(index)")
        }
    }

    private static func rig() throws -> Rig {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        let cards = CardStore()
        let atlas = try PreviewAtlas(resources: resources, byteBudget: 8 << 20, requestLimit: 16)
        var ids: [GreenItem] = []
        for card in try Self.cards() {
            cards.add(card)
            ids.append(.card(card.id))
            let preview = DecodedPreview(
                card: card.id,
                step: 128,
                width: 128,
                height: 96,
                outcome: .pixels([UInt8](repeating: 200, count: 128 * 96))
            )
            _ = atlas.store(preview, frame: 1)
        }
        let encoder = TextEncoder(
            resources: resources,
            store: TextStore(),
            cards: cards,
            atlas: GlyphAtlas(device: device, byteBudget: 16 << 20),
            ring: try GlyphRing(device: device, capacity: 4_096)
        )
        encoder.previews = atlas
        let texture = try resources.makeTarget(width: 800, height: 600, format: .rg8Unorm)
        let target = InkTarget(
            texture: texture,
            camera: Camera(center: .zero, zoom: 1),
            displayScale: 2
        )
        return Rig(encoder: encoder, target: target, ids: ids, resources: resources, atlas: atlas)
    }

    func testCardPassWithCachedPreviewsAllocatesNoMoreThanBarePass() throws {
        let rig = try Self.rig()
        var ours: [Int] = []
        var bare: [Int] = []
        for frame in 1...20 {
            let buffer = try XCTUnwrap(rig.resources.queue.makeCommandBuffer())
            let context = FrameContext(commandBuffer: buffer, frame: UInt64(frame + 1))
            rig.encoder.beginFrame()
            let count = AllocationCounter.countMainThread {
                _ = rig.encoder.encodePass(
                    context,
                    target: rig.target,
                    ids: rig.ids,
                    cursor: 0,
                    options: TextEncoder.Options()
                )
            }
            // The first frame draws the title glyphs into the glyph atlas.
            if frame > 1, let count { ours.append(count) }
            XCTAssertTrue(rig.atlas.wanted.isEmpty, "A cached preview asks for nothing")
            buffer.commit()
            buffer.waitUntilCompleted()
            if let count = try barePass(rig) { bare.append(count) }
        }
        let median = { (values: [Int]) in values.sorted()[values.count / 2] }
        let line = "card pass allocations p50 \(median(ours)), bare pass p50 \(median(bare))"
        XCTContext.runActivity(named: line) { _ in }
        XCTAssertLessThanOrEqual(median(ours), median(bare), line)
    }

    /// A render pass with the draws of the card pass: borders, previews, and one glyph run.
    private func barePass(_ rig: Rig) throws -> Int? {
        let other = try XCTUnwrap(rig.resources.queue.makeCommandBuffer())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = rig.target.texture
        pass.colorAttachments[0].loadAction = .load
        let count = AllocationCounter.countMainThread {
            guard let made = other.makeRenderCommandEncoder(descriptor: pass) else { return }
            made.setRenderPipelineState(rig.resources.cardBorderPipeline)
            made.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            made.setRenderPipelineState(rig.resources.glyphPipeline)
            made.setFragmentTexture(rig.atlas.texture, index: 0)
            made.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            made.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            made.endEncoding()
        }
        other.commit()
        other.waitUntilCompleted()
        return count
    }
}
