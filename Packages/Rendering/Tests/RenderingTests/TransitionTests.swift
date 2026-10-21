import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

/// The frames of an open and a leave on the renderer of the parent (m6-plan.md task 3.5, D-98,
/// D-108, D-109, D-110). The drawable has 400 x 240 pixels at scale 2, so the view shows 200 x
/// 120 view points. The card of the tests covers the screen at zoom 2, centered on (0, 5).
@MainActor
@Suite("Card transitions")
struct TransitionTests {
    private static let frame = Rect(
        origin: Point(x: -60, y: -25),
        size: Size(width: 120, height: 60)
    )
    private static let start = Camera(center: .zero, zoom: 1)
    private static let middle = Camera(center: Point(x: 0, y: 2.5), zoom: 1.5)
    private static let cover = Camera(center: Point(x: 0, y: 5), zoom: 2)

    private func makeLayer(renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.framebufferOnly = false
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// The renderer of a parent canvas, its layer, and its card.
    private struct Parent {
        let renderer: CanvasRenderer
        let layer: CAMetalLayer
        let card: Card
    }

    /// A parent with a line through the card, a text box beside it, and the card with its
    /// preview in the atlas.
    private func parent() async throws -> Parent {
        let source = FakePreviews(data: try FakePreviews.png(width: 300, height: 150))
        let renderer = try CanvasRenderer(previews: source)
        let layer = makeLayer(renderer: renderer)
        let card = try CardStoreTests.card(1, frame: Self.frame, title: "Tree")
        let line = (0...50).map { Point(x: -100 + Double($0) * 4, y: 30) }
        renderer.load([StrokeBuilder.stroke(line, seed: 1)])
        renderer.load([try TextRenderingTests.box("node", at: Point(x: -95, y: -55))])
        renderer.load([card])
        for _ in 0..<2_000 where Self.isLoading(renderer, source) {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
        return Parent(renderer: renderer, layer: layer, card: card)
    }

    /// `true` while the titles, the text, or the preview of the parent load.
    private static func isLoading(_ renderer: CanvasRenderer, _ source: FakePreviews) -> Bool {
        renderer.isLoadingCards || renderer.isLoadingText || renderer.isLoadingPreviews
            || source.readCount == 0
    }

    /// Draws one frame into a new drawable and reads it.
    private func capture(_ renderer: CanvasRenderer, layer: CAMetalLayer) throws -> RenderedImage {
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
        let drawable = try #require(layer.nextDrawable())
        let size = layer.drawableSize
        _ = renderer.engine.withRenderer { frames in
            frames.renderFrame(drawableSize: size, deadline: nil, drawable: .drawable(drawable))
        }
        let pixels = try DrawableCapture.read(drawable.texture, renderer: renderer)
        return RenderedImage(width: 400, height: 240, pixels: pixels)
    }

    private static func limit() -> Int { Int(Double(400 * 240) * Snapshot.tolerance) }

    @Test("An open freezes the parent, frees its textures, and shrinks the parent to the card")
    func open() async throws {
        let parent = try await parent()
        let (renderer, layer, card) = (parent.renderer, parent.layer, parent.card)
        let before = try capture(renderer, layer: layer)
        renderer.beginOpen(of: card.id)
        let first = try capture(renderer, layer: layer)
        let isFreed = renderer.engine.withRenderer { frames in
            let frozenWidth = frames.transition?.frozen?.texture.width ?? 0
            return frames.layer == nil && frozenWidth > 0
        }
        #expect(isFreed, "The open freed the committed textures and kept a frozen copy")
        #expect(
            Snapshot.differingPixels(first, before) <= Self.limit(),
            "The start equals the parent"
        )
        Snapshot.assertMatches(first, named: "open-start")
        renderer.camera = Self.middle
        renderer.setParentWeight(0.5)
        Snapshot.assertMatches(try capture(renderer, layer: layer), named: "open-middle")
        renderer.camera = Self.cover
        renderer.setParentWeight(0)
        let end = try capture(renderer, layer: layer)
        // The cross of the preview meets at the center of the card, the center of the screen.
        #expect(end.gray(x: 200, y: 120) > 200, "The preview covers the screen")
        #expect(end.gray(x: 20, y: 20) < 100, "No parent ink shows")
        Snapshot.assertMatches(end, named: "open-end")
    }

    @Test("A leave grows the parent from the card back to the live parent")
    func leave() async throws {
        let parent = try await parent()
        let (renderer, layer, card) = (parent.renderer, parent.layer, parent.card)
        let parentImage = try capture(renderer, layer: layer)
        renderer.camera = Self.cover
        renderer.beginLeave(into: card.id)
        let start = try capture(renderer, layer: layer)
        #expect(start.gray(x: 200, y: 120) > 200, "The leave starts with the card alone")
        Snapshot.assertMatches(start, named: "leave-start")
        renderer.camera = Self.middle
        renderer.setParentWeight(0.5)
        Snapshot.assertMatches(try capture(renderer, layer: layer), named: "leave-middle")
        renderer.camera = Self.start
        renderer.setParentWeight(1)
        let end = try capture(renderer, layer: layer)
        Snapshot.assertMatches(end, named: "leave-end")
        renderer.endTransition()
        let after = try capture(renderer, layer: layer)
        // The zoom of the leave loaded a larger preview, so the parent after the leave is the
        // reference, not the parent before it.
        #expect(Snapshot.differingPixels(end, after) <= Self.limit(), "The end is the parent")
        #expect(parentImage.gray(x: 20, y: 180) == after.gray(x: 20, y: 180), "The ink stays")
    }
}
