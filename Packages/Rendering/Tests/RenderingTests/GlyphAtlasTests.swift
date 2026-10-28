import Geometry
import Metal
import Model
import Testing
import UIKit

@testable import Rendering

@Suite("Glyph atlas")
@MainActor
struct GlyphAtlasTests {
    private static func atlas(budget: Int = 16 << 20) throws -> GlyphAtlas {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return GlyphAtlas(device: device, byteBudget: budget)
    }

    private static let font = TextLayout.font(size: TextStyle.fontSize)

    private static func glyph(_ text: String) throws -> TextLayout.Glyph {
        try #require(TextLayout(text: text).glyphs.first)
    }

    @Test("The scale is the next power of two of the pixels per point, inside the range")
    func exponent() {
        #expect(GlyphAtlas.exponent(pixelsPerCanvasPoint: 1) == 0)
        #expect(GlyphAtlas.exponent(pixelsPerCanvasPoint: 1.5) == 1)
        #expect(GlyphAtlas.exponent(pixelsPerCanvasPoint: 2) == 1)
        #expect(GlyphAtlas.exponent(pixelsPerCanvasPoint: 0.5) == -1)
        #expect(GlyphAtlas.exponent(pixelsPerCanvasPoint: 0.01) == -2)
        #expect(GlyphAtlas.exponent(pixelsPerCanvasPoint: 1_000) == 5)
    }

    @Test("A glyph at two scales has two bitmaps, the larger one twice the size")
    func twoScales() throws {
        let atlas = try Self.atlas()
        let glyph = try Self.glyph("M")
        let small = try #require(
            atlas.placement(of: glyph.glyph, font: Self.font, exponent: 1, frame: 1)
        )
        let large = try #require(
            atlas.placement(of: glyph.glyph, font: Self.font, exponent: 2, frame: 1)
        )
        #expect(small.page != large.page)
        #expect(abs(large.size.y - 2 * small.size.y) <= 2)
        #expect(large.bearing.y < 0 && small.bearing.y < 0)
        let again = atlas.placement(of: glyph.glyph, font: Self.font, exponent: 1, frame: 2)
        #expect(again == small)
    }

    @Test("A drop of the last page of a heap frees the heap (3.2.11)")
    func dropFreesHeap() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let atlas = GlyphAtlas(device: device, byteBudget: 16 << 20, isBindless: true)
        let table = try #require(atlas.pageTable)
        let glyph = try Self.glyph("M")
        _ = try #require(atlas.placement(of: glyph.glyph, font: Self.font, exponent: 1, frame: 1))
        #expect(table.heaps.count == 1)
        #expect(atlas.pages[0] != nil)
        atlas.drop(0)
        #expect(table.heaps.isEmpty, "The chunk of the last page goes with the page")
    }

    @Test("A space has no bitmap")
    func space() throws {
        let atlas = try Self.atlas()
        let space = try Self.glyph(" ")
        let placement = atlas.placement(of: space.glyph, font: Self.font, exponent: 1, frame: 1)
        #expect(placement?.page == -1)
        #expect(atlas.byteCount == 0)
    }

    @Test("A fallback glyph gets a bitmap of its own font (D-84)")
    func fallback() throws {
        let atlas = try Self.atlas()
        let layout = TextLayout(text: "漢")
        let glyph = try #require(layout.glyphs.first)
        let placement = atlas.placement(
            of: glyph.glyph,
            font: layout.fonts[Int(layout.fontIndices[0])],
            exponent: 1,
            frame: 1
        )
        #expect((placement?.size.x ?? 0) > 0)
    }

    @Test("Past the budget, the page that a frame used least recently goes first")
    func budget() throws {
        // The two smallest scales have pages of the same size, so one page fills the budget.
        let side = GlyphAtlas.pageSide(exponent: -2)
        #expect(GlyphAtlas.pageSide(exponent: -1) == side)
        let atlas = try Self.atlas(budget: side * side)
        let glyph = try Self.glyph("M")
        let first = atlas.placement(of: glyph.glyph, font: Self.font, exponent: -2, frame: 1)
        #expect(first != nil)
        let second = atlas.placement(of: glyph.glyph, font: Self.font, exponent: -1, frame: 2)
        #expect(second != nil)
        #expect(atlas.byteCount == side * side)
        #expect(atlas.pages.compactMap { $0?.exponent } == [-1])
    }

    @Test("A page that the current frame uses never goes, and the atlas then refuses")
    func budgetInUse() throws {
        let page = GlyphAtlas.pageSide(exponent: 0) * GlyphAtlas.pageSide(exponent: 0)
        let atlas = try Self.atlas(budget: page)
        let glyph = try Self.glyph("M")
        #expect(atlas.placement(of: glyph.glyph, font: Self.font, exponent: 0, frame: 5) != nil)
        #expect(atlas.placement(of: glyph.glyph, font: Self.font, exponent: -1, frame: 5) == nil)
        #expect(atlas.byteCount == page)
    }
}
