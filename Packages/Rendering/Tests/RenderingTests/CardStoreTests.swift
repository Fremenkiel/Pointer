import Foundation
import Geometry
import Model
import QuartzCore
import Testing

@testable import Rendering

/// The card store of the renderer (architecture.md 5.5 and 5.6, D-92, D-96).
@MainActor
@Suite("Card store")
struct CardStoreTests {
    /// Makes a card with `frame` and `title`.
    static func card(
        _ id: UInt8,
        frame: Rect = Rect(origin: Point(x: -50, y: -35), size: Size(width: 100, height: 70)),
        title: String? = "Card"
    ) throws -> Card {
        let device = DeviceID(
            rawValue: UUID(uuid: (9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
        return try Card(
            id: CardID(rawValue: UUID(uuid: (6, id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            meta: RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: device)),
            canvasID: CanvasID(
                rawValue: UUID(uuid: (7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            ),
            frame: frame,
            title: title,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    private func makeLayer(renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// Waits for the title layout of a load, which runs off the render thread (D-92), and draws
    /// the frames until the renderer needs no more.
    private func drain(_ renderer: CanvasRenderer, layer: CAMetalLayer) {
        for _ in 0..<2_000 where renderer.isLoadingCards || renderer.isLoadingText {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            Thread.sleep(forTimeInterval: 0.001)
        }
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
    }

    @Test("A load lays out each title off the render thread and fills the store and the grid")
    func load() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let long = String(repeating: "m", count: Limits.maxTitleLength)
        let cards = [
            try Self.card(1, title: "Tree"), try Self.card(2, title: nil),
            try Self.card(3, title: long), try Self.card(4, title: ""),
        ]
        renderer.load(cards)
        drain(renderer, layer: layer)
        #expect(!renderer.isLoadingCards)
        let (count, lines, found) = renderer.engine.withRenderer { frames in
            var found = 0
            let area = Rect(minX: -60, minY: -45, maxX: 60, maxY: 45)
            frames.cards.grid.forEachItem(touching: area) { _ in found += 1 }
            var lines: [Int] = []
            for card in cards {
                lines.append(frames.cards.entries[card.id]?.layout?.lineCount ?? 0)
            }
            return (frames.cards.count, lines, found)
        }
        #expect(count == 4)
        #expect(found == 4)
        #expect(lines[0] == 1)
        #expect(lines[1] == 0)
        // 120 characters of SF Mono at 17 points pass the wrap width of 640 points (D-84).
        #expect(lines[2] == 2)
        #expect(lines[3] == 0)
    }

    @Test("The bounds hold the frame and the title above its top-left corner")
    func bounds() throws {
        let store = CardStore()
        let card = try Self.card(1, title: "A title")
        store.add(card)
        let entry = try #require(store.entries[card.id])
        let layout = try #require(entry.layout)
        let origin = try #require(entry.titleOrigin)
        #expect(origin == Point(x: card.frame.minX, y: card.frame.minY - layout.size.height))
        #expect(entry.bounds.minY < origin.y)
        #expect(entry.bounds.maxY > card.frame.maxY)
        #expect(entry.bounds.minX < card.frame.minX)
        #expect(entry.bounds.maxX > max(card.frame.maxX, origin.x + layout.size.width))
        #expect(store.grid.bounds(of: card.id) == entry.bounds)
        let untitled = try Self.card(2, title: nil)
        store.add(untitled)
        #expect(store.entries[untitled.id]?.titleOrigin == nil)
    }

    @Test("A change removes, replaces, and adds cards")
    func change() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let first = try Self.card(1)
        let second = try Self.card(2, title: "old")
        renderer.load([first, second])
        drain(renderer, layer: layer)
        let renamed = try second.retitling("new", at: second.meta.modified)
        let third = try Self.card(3)
        renderer.changeCards(removing: [first.id], adding: [renamed, third])
        drain(renderer, layer: layer)
        let (ids, title) = renderer.engine.withRenderer { frames in
            (Set(frames.cards.entries.keys), frames.cards.entries[second.id]?.title)
        }
        #expect(ids == [second.id, third.id])
        #expect(title == "new")
    }

    @Test("A move keeps the title layout, and a new title lays out again")
    func moveKeepsLayout() throws {
        let store = CardStore()
        let card = try Self.card(1, title: "Tree")
        // A stand-in layout with 5 glyphs shows whether the move lays out "Tree" again.
        store.insert(card, layout: TextLayout(text: "other"))
        let moved = try card.moving(to: Point(x: 900, y: -400), at: card.meta.modified)
        let earlier = store.add(moved)
        #expect(earlier != nil)
        #expect(store.entries[card.id]?.layout?.glyphs.count == 5)
        #expect(store.entries[card.id]?.frame == moved.frame)
        store.add(try moved.retitling("Graphs", at: card.meta.modified))
        #expect(store.entries[card.id]?.layout?.glyphs.count == 6)
        #expect(store.entries[card.id]?.title == "Graphs")
        #expect(store.remove(card.id) != nil)
        #expect(store.count == 0)
        #expect(store.grid.count == 0)
    }

    @Test("An edit of a card during its load wins over the loaded card")
    func editDuringLoad() throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let card = try Self.card(1, title: "loaded")
        let edited = try card.retitling("edited", at: card.meta.modified)
        renderer.load([card])
        renderer.changeCards(removing: [], adding: [edited])
        drain(renderer, layer: layer)
        let title = renderer.engine.withRenderer { $0.cards.entries[card.id]?.title }
        #expect(title == "edited")
    }
}
