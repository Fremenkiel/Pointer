import Foundation
import Geometry
import Metal
import Model
import Testing

@testable import Rendering

/// The stored glyph runs of the text (architecture.md 5.4.1, D-94, D-188 to D-190): the same
/// pixels as the CPU path, a run that a frame reuses, and a run that builds again after an edit
/// or a page drop.
@MainActor
@Suite("Stored glyph runs")
struct StoredGlyphTests {
    /// The texts of the boxes: SF Mono, a fallback font, and an emoji as a white shape. Each
    /// has at least `StoredText.minimumGlyphs` glyphs, so that it takes a stored run.
    static let texts = [
        String(repeating: "node -> next ", count: 12),
        String(repeating: "Graph G = (V, E)\nBFS: queue, DFS: stack\n", count: 4),
        String(repeating: "λ → μ, 図 グラフ, 😀 ", count: 12),
    ]

    /// An encoder over a store, and a committed target at a zoom.
    struct Rig {
        let encoder: TextEncoder
        let store: TextStore
        let resources: InkResources
        let target: InkTarget
        let ids: [GreenItem]
    }

    static func box(_ text: String, index: Int, origin: Point) throws -> TextBox {
        let byte = UInt8(index + 1)
        return try TextBox(
            id: TextBoxID(
                rawValue: UUID(uuid: (4, byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            ),
            meta: RecordMeta(
                created: HybridTimestamp(
                    wallMillis: 1,
                    counter: 0,
                    device: DeviceID(rawValue: UUID())
                )
            ),
            canvasID: CanvasID(rawValue: UUID()),
            origin: origin,
            text: text,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    private static func rig(
        isStored: Bool,
        zoom: Double = 1,
        atlasBudget: Int = 16 << 20
    ) throws -> Rig {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        let store = TextStore()
        for (index, text) in texts.enumerated() {
            store.add(
                try box(text, index: index, origin: Point(x: -180, y: -90 + 60 * Double(index)))
            )
        }
        let atlas = GlyphAtlas(device: device, byteBudget: atlasBudget, isBindless: isStored)
        let stored =
            isStored
            ? try StoredText(device: device, capacity: 16_384, runByteBudget: 4 << 20) : nil
        let encoder = TextEncoder(
            resources: resources,
            store: store,
            atlas: atlas,
            ring: try GlyphRing(device: device, capacity: 4_096),
            stored: stored
        )
        let target = InkTarget(
            texture: try resources.makeTarget(
                width: 800,
                height: 480,
                format: InkResources.committedFormat,
                isReadable: true
            ),
            camera: Camera(center: .zero, zoom: zoom),
            displayScale: 2
        )
        var ids: [GreenItem] = []
        store.grid.forEachItem(touching: target.canvasRect) { ids.append(.textBox($0)) }
        return Rig(encoder: encoder, store: store, resources: resources, target: target, ids: ids)
    }

    /// Draws one pass of all boxes into the target, with a clear first, and waits for the GPU.
    static func draw(_ rig: Rig, frame: UInt64, target: InkTarget? = nil) throws {
        let target = target ?? rig.target
        let buffer = try #require(rig.resources.queue.makeCommandBuffer())
        rig.encoder.beginFrame()
        var options = TextEncoder.Options()
        options.scissor = MTLScissorRect(
            x: 0,
            y: 0,
            width: target.texture.width,
            height: target.texture.height
        )
        options.clearsScissor = true
        let cursor = rig.encoder.encodePass(
            FrameContext(commandBuffer: buffer, frame: frame),
            target: target,
            ids: rig.ids,
            cursor: 0,
            options: options
        )
        #expect(cursor == rig.ids.count, "One pass holds the boxes")
        buffer.commit()
        buffer.waitUntilCompleted()
        #expect(buffer.status == .completed)
    }

    @Test("The stored runs draw the pixels of the CPU path", arguments: [0.25, 1.0, 8.0])
    func samePixels(zoom: Double) throws {
        let stored = try Self.rig(isStored: true, zoom: zoom)
        let cpu = try Self.rig(isStored: false, zoom: zoom)
        try Self.draw(stored, frame: 1)
        try Self.draw(cpu, frame: 1)
        #expect(stored.encoder.ring.used == 0, "No glyph took the CPU path")
        #expect(stored.encoder.stored?.runs.runs.count == stored.ids.count)
        let ours = CoverageReader.pixels(of: stored.target.texture, channel: 1)
        let theirs = CoverageReader.pixels(of: cpu.target.texture, channel: 1)
        #expect(theirs.contains { $0 > 0 }, "The text shows")
        let differing = zip(ours, theirs).filter { abs(Int($0) - Int($1)) > 8 }.count
        // The tolerance of the snapshot tests (TEST-07). A rounding tie can move a glyph.
        #expect(differing <= ours.count / 200, "\(differing) of \(ours.count) pixels differ")
    }

    @Test("A later frame reuses the runs, and a move keeps them")
    func reuse() throws {
        let rig = try Self.rig(isStored: true)
        try Self.draw(rig, frame: 1)
        let first = try #require(rig.encoder.stored?.runs.runs)
        try Self.draw(rig, frame: 2)
        let box = try Self.box(Self.texts[0], index: 0, origin: Point(x: -170, y: -90))
        rig.store.add(box)
        try Self.draw(rig, frame: 3)
        let after = try #require(rig.encoder.stored?.runs.runs)
        #expect(after.mapValues(\.block) == first.mapValues(\.block))
        #expect(after.values.allSatisfy { $0.lastFrame == 3 })
    }

    @Test("An edit of the text builds the run again")
    func edit() throws {
        let rig = try Self.rig(isStored: true)
        try Self.draw(rig, frame: 1)
        let key = GlyphRunStore.Key(item: rig.ids[0], exponent: 1)
        let before = try #require(rig.encoder.stored?.runs.runs[key])
        guard case .textBox(let id) = rig.ids[0] else {
            Issue.record("The first item is a text box")
            return
        }
        let index = Self.texts.firstIndex { rig.store.entries[id]?.text == $0 } ?? 0
        let origin = try #require(rig.store.entries[id]?.origin)
        rig.store.add(
            try Self.box(String(repeating: "changed ", count: 20), index: index, origin: origin)
        )
        try Self.draw(rig, frame: 2)
        let after = try #require(rig.encoder.stored?.runs.runs[key])
        #expect(after.version != before.version)
        #expect(after.count == 140, "7 letters with pixels, 20 times")
    }

    @Test("A layout below the fewest glyphs of a run takes the CPU path")
    func shortText() throws {
        let rig = try Self.rig(isStored: true)
        guard case .textBox(let id) = rig.ids[0], let origin = rig.store.entries[id]?.origin
        else {
            Issue.record("The first item is a text box")
            return
        }
        let index = Self.texts.firstIndex { rig.store.entries[id]?.text == $0 } ?? 0
        rig.store.add(try Self.box("short", index: index, origin: origin))
        try Self.draw(rig, frame: 1)
        let key = GlyphRunStore.Key(item: rig.ids[0], exponent: 1)
        #expect(rig.encoder.stored?.runs.runs[key] == nil)
        #expect(rig.encoder.ring.used == 5, "The CPU path wrote the 5 glyphs")
    }

    @Test("A dropped page builds the runs that read it again")
    func pageDrop() throws {
        // A budget of one page of exponent 1 (1,024 pixels): a page of another exponent drops it.
        let rig = try Self.rig(isStored: true, atlasBudget: 1 << 20)
        try Self.draw(rig, frame: 1)
        let key = GlyphRunStore.Key(item: rig.ids[0], exponent: 1)
        let before = try #require(rig.encoder.stored?.runs.runs[key])
        let small = InkTarget(
            texture: rig.target.texture,
            camera: Camera(center: .zero, zoom: 0.25),
            displayScale: 1
        )
        try Self.draw(rig, frame: 10, target: small)
        let atlas = rig.encoder.atlas
        let page = try #require(before.pages.first)
        #expect(atlas.generations[page] != before.generations[0], "The page was dropped")
        #expect(
            rig.encoder.stored?.runs.validRun(key, version: before.version, atlas: atlas, frame: 11)
                == nil
        )
        try Self.draw(rig, frame: 20)
        #expect(rig.encoder.stored?.runs.runs[key] != nil, "The run built again")
    }

    @Test("Past the budget, an old run of another exponent goes, and one of the same after its age")
    func eviction() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        // One slab: 16,384 quads.
        let store = try GlyphRunStore(
            device: device,
            byteBudget: SlabAllocator.slabPoints * GlyphRunStore.bytesPerQuad
        )
        let quads = [StoredGlyph](
            repeating: StoredGlyph(x: 0, line: 0, place: 0),
            count: 10_000
        )
        let item = { GreenItem.textBox(TextBoxID(rawValue: UUID())) }
        let first = GlyphRunStore.Key(item: item(), exponent: 0)
        let other = GlyphRunStore.Key(item: item(), exponent: 1)
        let same = GlyphRunStore.Key(item: item(), exponent: 1)
        let pages = (indices: [0], generations: [UInt32(0)])
        #expect(store.store(quads, key: first, version: 1, pages: pages, frame: 1) != nil)
        #expect(
            store.store(quads, key: other, version: 1, pages: pages, frame: 4) == nil,
            "The run of frame 1 is in flight"
        )
        #expect(store.store(quads, key: other, version: 1, pages: pages, frame: 5) != nil)
        #expect(store.runs[first] == nil, "A run of another exponent went")
        let age = GlyphRunStore.sameExponentAge
        #expect(
            store.store(quads, key: same, version: 1, pages: pages, frame: 5 + age) == nil,
            "A run of the same exponent stays for its age"
        )
        #expect(store.store(quads, key: same, version: 1, pages: pages, frame: 6 + age) != nil)
        #expect(store.runs[other] == nil, "The old run of the same exponent went")
        #expect(store.footprint <= store.byteBudget)
    }
}
