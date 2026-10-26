import Geometry
import Metal
import Model
import Testing

@testable import Rendering

/// The start of the stored runs (architecture.md 5.4.1): a canvas of cards and short text keeps
/// the CPU path and the textures of the device, and the first large layout starts the runs in
/// the next pass.
@MainActor
@Suite("Start of the stored glyph runs")
struct StoredGlyphStartTests {
    /// An encoder that makes its stored runs on its own, over one box of short text.
    private static func rig() throws -> StoredGlyphTests.Rig {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        let store = TextStore()
        let encoder = TextEncoder(
            resources: resources,
            store: store,
            atlas: GlyphAtlas(device: device, byteBudget: 16 << 20),
            ring: try GlyphRing(device: device, capacity: 4_096),
            storedLimits: (16_384, 4 << 20)
        )
        store.add(try StoredGlyphTests.box("short", index: 0, origin: Point(x: -180, y: -90)))
        let target = InkTarget(
            texture: try resources.makeTarget(
                width: 800,
                height: 480,
                format: InkResources.committedFormat
            ),
            camera: Camera(center: .zero, zoom: 1),
            displayScale: 2
        )
        var ids: [GreenItem] = []
        store.grid.forEachItem(touching: target.canvasRect) { ids.append(.textBox($0)) }
        return StoredGlyphTests.Rig(
            encoder: encoder,
            store: store,
            resources: resources,
            target: target,
            ids: ids
        )
    }

    @Test("The stored runs start in the pass after the first large layout, and not for short text")
    func lazyStart() throws {
        let rig = try Self.rig()
        let (encoder, store) = (rig.encoder, rig.store)
        try StoredGlyphTests.draw(rig, frame: 1)
        try StoredGlyphTests.draw(rig, frame: 2)
        #expect(encoder.stored == nil, "Short text keeps the CPU path")
        #expect(encoder.atlas.pageTable == nil, "The atlas keeps the textures of the device")
        store.add(
            try StoredGlyphTests.box(
                StoredGlyphTests.texts[0],
                index: 0,
                origin: Point(x: -180, y: -90)
            )
        )
        try StoredGlyphTests.draw(rig, frame: 3)
        #expect(encoder.stored == nil, "The first large layout takes the CPU path")
        #expect(encoder.ring.used > 0)
        try StoredGlyphTests.draw(rig, frame: 4)
        #expect(encoder.stored?.runs.runs.count == 1, "The next pass stores the run")
        #expect(encoder.atlas.pageTable != nil)
        #expect(encoder.ring.used == 0)
    }
}
