import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

/// The cards of the committed layer: the border and the title in the green channel, under the
/// ink and the eraser mask (architecture.md 5.5, D-82, D-96). The drawable has 400 x 240 pixels
/// at scale 2, so the view shows 200 x 120 view points.
@MainActor
@Suite("Card rendering")
struct CardRenderingTests {
    /// The eraser radius in view points (architecture.md 4.4).
    private static let radius = 8.0
    /// The card of the tests: its left border is at pixel x 80 at zoom 1.
    private static let frame = Rect(
        origin: Point(x: -60, y: -25),
        size: Size(width: 120, height: 60)
    )
    /// The pixel values that count as the gray border of D-96, with a coverage of 0.5.
    private static let borderGray: ClosedRange<UInt8> = 100...160

    private func makeLayer(renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        // The capture copies the drawable, so the layer must allow a blit.
        layer.framebufferOnly = false
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// Waits for the layouts of a load, which run off the render thread (D-92), and draws the
    /// frames until the renderer needs no more.
    private func drain(_ renderer: CanvasRenderer, layer: CAMetalLayer) async throws {
        for _ in 0..<2_000 where renderer.isLoadingCards || renderer.isLoadingText {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
    }

    /// Draws one frame into a new drawable and reads it, as `TextRenderingTests` does.
    private func capture(_ renderer: CanvasRenderer, layer: CAMetalLayer) throws -> RenderedImage {
        let drawable = try #require(layer.nextDrawable())
        let size = layer.drawableSize
        _ = renderer.engine.withRenderer { frames in
            frames.renderFrame(drawableSize: size, deadline: nil, drawable: .drawable(drawable))
        }
        let pixels = try DrawableCapture.read(drawable.texture, renderer: renderer)
        return RenderedImage(width: 400, height: 240, pixels: pixels)
    }

    private func fresh(
        _ renderer: CanvasRenderer,
        strokes: [Stroke] = [],
        textBoxes: [TextBox] = [],
        cards: [Card]
    ) throws -> RenderedImage {
        try renderer.renderImage(
            of: strokes,
            textBoxes: textBoxes,
            cards: cards,
            camera: Camera(center: .zero, zoom: 1),
            viewSize: Size(width: 200, height: 120),
            displayScale: 2
        )
    }

    /// A horizontal line through the left border of the card.
    private static let line = StrokeBuilder.stroke(
        (0...50).map { Point(x: -100 + Double($0) * 2, y: 0) },
        seed: 1
    )

    @Test("A card shows a gray border and a white title at the zoom", arguments: [0.25, 1.0, 4.0])
    func snapshot(zoom: Double) async throws {
        let renderer = try CanvasRenderer()
        let card = try CardStoreTests.card(1, frame: Self.frame, title: "Tree")
        // At zoom 4, the camera looks at the top-left corner, where the title starts.
        let center = zoom > 1 ? Self.frame.origin : .zero
        let image = try renderer.renderImage(
            of: [],
            cards: [card],
            camera: Camera(center: center, zoom: zoom),
            viewSize: Size(width: 200, height: 120),
            displayScale: 2
        )
        let border = image.gray(x: 80, y: 120)
        if zoom == 1 {
            #expect(Self.borderGray.contains(border), "The border is gray, got \(border)")
        }
        let lit = (0..<(image.width * image.height)).filter { image.pixels[$0 * 4 + 1] > 200 }
        #expect(!lit.isEmpty, "The title shows")
        Snapshot.assertMatches(image, named: "card-zoom\(zoom)")
    }

    @Test("Ink over a card shows white, and the border beside it stays gray (D-16)")
    func underInk() async throws {
        let renderer = try CanvasRenderer()
        let card = try CardStoreTests.card(1, frame: Self.frame, title: "Tree")
        let image = try fresh(renderer, strokes: [Self.line], cards: [card])
        #expect(image.gray(x: 80, y: 120) > 240, "The ink covers the border")
        #expect(Self.borderGray.contains(image.gray(x: 80, y: 150)), "The border stays gray")
        Snapshot.assertMatches(image, named: "card-under-ink")
    }

    @Test("The eraser mask hides the ink over a card and never the card (D-82)")
    func underEraserMask() async throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        renderer.load([Self.line])
        renderer.load([try CardStoreTests.card(1, frame: Self.frame, title: "Tree")])
        try await drain(renderer, layer: layer)
        let before = try capture(renderer, layer: layer)
        renderer.setEraserReady(true)
        renderer.beginErase(radius: Self.radius)
        for step in 0...4 {
            renderer.addEraserSample(Point(x: 40, y: 56 + Double(step) * 2))
        }
        try await drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        #expect(before.gray(x: 80, y: 120) > 240, "The ink covers the border before the erase")
        let border = image.gray(x: 80, y: 120)
        #expect(Self.borderGray.contains(border), "The border shows under the mask, got \(border)")
        #expect(image.gray(x: 70, y: 120) < 8, "The ink outside the card under the mask is hidden")
        #expect(image.gray(x: 120, y: 120) > 240, "The ink beside the eraser stays")
        Snapshot.assertMatches(image, named: "card-under-eraser-mask")
    }

    @Test("A moved card leaves no old pixels, and its new place equals a fresh draw")
    func moveRedraw() async throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let card = try CardStoreTests.card(1, frame: Self.frame, title: "Tree")
        let moved = try card.moving(to: Point(x: -20, y: -10), at: card.meta.modified)
        renderer.load([card])
        try await drain(renderer, layer: layer)
        renderer.placeCard(moved)
        try await drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        let limit = Int(Double(400 * 240) * Snapshot.tolerance)
        #expect(Snapshot.differingPixels(image, try fresh(renderer, cards: [moved])) <= limit)
        Snapshot.assertMatches(image, named: "card-move-redraw")
    }

    @Test("A text change over a card clears the green channel and keeps the card")
    func textOverCardRedraw() async throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let card = try CardStoreTests.card(1, frame: Self.frame, title: "Tree")
        let box = try TextRenderingTests.box("node", at: Point(x: -70, y: -10))
        let moved = try TextRenderingTests.box("node", at: Point(x: 0, y: 5))
        renderer.load([card])
        renderer.load([box])
        try await drain(renderer, layer: layer)
        renderer.placeTextBox(moved)
        try await drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        let expected = try fresh(renderer, textBoxes: [moved], cards: [card])
        let limit = Int(Double(400 * 240) * Snapshot.tolerance)
        #expect(Snapshot.differingPixels(image, expected) <= limit)
        #expect(Self.borderGray.contains(image.gray(x: 80, y: 120)), "The border stays")
        Snapshot.assertMatches(image, named: "text-over-card-redraw")
    }

    @Test("A card shows its preview inside its border at zoom 1 (D-97)")
    func preview() async throws {
        let source = FakePreviews(data: try FakePreviews.png(width: 300, height: 150))
        let renderer = try CanvasRenderer(previews: source)
        let layer = makeLayer(renderer: renderer)
        renderer.load([try CardStoreTests.card(1, frame: Self.frame, title: "Tree")])
        // The preview loads off the render thread after the first frames.
        for _ in 0..<2_000
        where renderer.isLoadingCards || renderer.isLoadingPreviews || source.readCount == 0 {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        try await drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        #expect(source.readCount == 1)
        // The cross of the preview crosses the center of the card: canvas (0, 5).
        #expect(image.gray(x: 200, y: 130) > 200, "The preview shows")
        #expect(
            Self.borderGray.contains(image.gray(x: 80, y: 150)) || image.gray(x: 80, y: 150) > 200
        )
        Snapshot.assertMatches(image, named: "card-preview")
    }

    @Test("A card change over a text box keeps the text, and a removed card leaves the screen")
    func cardOverTextRedraw() async throws {
        let renderer = try CanvasRenderer()
        let layer = makeLayer(renderer: renderer)
        let card = try CardStoreTests.card(1, frame: Self.frame, title: "Tree")
        let box = try TextRenderingTests.box("node", at: Point(x: -70, y: -10))
        renderer.load([card])
        renderer.load([box])
        try await drain(renderer, layer: layer)
        renderer.changeCards(removing: [card.id], adding: [])
        try await drain(renderer, layer: layer)
        let image = try capture(renderer, layer: layer)
        let limit = Int(Double(400 * 240) * Snapshot.tolerance)
        let expected = try fresh(renderer, textBoxes: [box], cards: [])
        #expect(Snapshot.differingPixels(image, expected) <= limit)
        #expect(image.gray(x: 80, y: 150) < 8, "The border left the screen")
    }
}
