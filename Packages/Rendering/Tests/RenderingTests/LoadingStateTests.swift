import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Synchronization
import Testing

@testable import Rendering

/// The loading state between the take of the inbox and the apply of the frame (review after M9,
/// section 3.2, item 1). A wait on the old flags could end in that gap with work left.
@MainActor
@Suite("Loading state of the renderer")
struct LoadingStateTests {
    /// The flags that the hook read after each take: text, cards, previews, and all.
    private final class Seen: Sendable {
        let values = Mutex<[[Bool]]>([])
    }

    private static func renderer(
        previews: (any PreviewSource)? = nil,
        seen: Seen
    ) throws -> CanvasRenderer {
        try CanvasRenderer(
            configuration: RendererConfiguration(),
            previews: previews,
            afterTake: { engine in
                let flags = [
                    engine.isLoadingText, engine.isLoadingCards, engine.isLoadingPreviews,
                    engine.isLoading,
                ]
                seen.values.withLock { $0.append(flags) }
            },
            afterCameraLock: nil
        )
    }

    private static func layer(for renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// Waits until `isWaiting` reads `false` in the inbox, without a frame.
    private static func waitForInbox(
        _ renderer: CanvasRenderer,
        while isWaiting: (RenderInbox) -> Bool
    ) async throws {
        for _ in 0..<2_000 where renderer.engine.inbox.withLock({ isWaiting($0) }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(!renderer.engine.inbox.withLock { isWaiting($0) }, "The layout came in time")
    }

    @Test("Loaded text counts as loading after the take, until its frame applies it")
    func textAfterTake() async throws {
        let seen = Seen()
        let renderer = try Self.renderer(seen: seen)
        let layer = Self.layer(for: renderer)
        renderer.load([try TextRenderingTests.box("node", at: .zero)])
        try await Self.waitForInbox(renderer) { $0.laidOutText.isEmpty }
        _ = renderer.renderFrame(into: layer, deadline: nil)
        let first = try #require(seen.values.withLock { $0.first })
        #expect(first[0], "isLoadingText after the take")
        #expect(first[3], "isLoading after the take")
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
        #expect(!renderer.isLoading)
    }

    @Test("Loaded cards count as loading after the take, until their frame applies them")
    func cardsAfterTake() async throws {
        let seen = Seen()
        let renderer = try Self.renderer(seen: seen)
        let layer = Self.layer(for: renderer)
        let frame = Rect(origin: Point(x: -60, y: -40), size: Size(width: 120, height: 80))
        renderer.load([try CardStoreTests.card(1, frame: frame, title: "Tree")])
        try await Self.waitForInbox(renderer) { $0.laidOutCards.isEmpty }
        _ = renderer.renderFrame(into: layer, deadline: nil)
        let first = try #require(seen.values.withLock { $0.first })
        #expect(first[1], "isLoadingCards after the take")
        #expect(first[3], "isLoading after the take")
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
        #expect(!renderer.isLoading)
    }

    @Test("A decoded preview counts as loading after the take, until its upload")
    func previewAfterTake() async throws {
        let seen = Seen()
        let source = FakePreviews(data: try FakePreviews.png(width: 300, height: 150))
        let renderer = try Self.renderer(previews: source, seen: seen)
        let layer = Self.layer(for: renderer)
        let frame = Rect(origin: Point(x: -60, y: -40), size: Size(width: 120, height: 80))
        renderer.load([try CardStoreTests.card(1, frame: frame, title: "Tree")])
        // The frames ask for the preview, and the loader decodes it off the render thread.
        for _ in 0..<2_000 where renderer.engine.inbox.withLock({ $0.decodedPreviews.isEmpty }) {
            _ = renderer.renderFrame(into: layer, deadline: nil)
            try await Task.sleep(for: .milliseconds(1))
        }
        seen.values.withLock { $0.removeAll() }
        #expect(!renderer.engine.inbox.withLock { $0.decodedPreviews.isEmpty })
        _ = renderer.renderFrame(into: layer, deadline: nil)
        let first = try #require(seen.values.withLock { $0.first })
        #expect(first[2], "isLoadingPreviews after the take")
        #expect(first[3], "isLoading after the take")
        for _ in 0..<100 where renderer.renderFrame(into: layer, deadline: nil) {}
        #expect(!renderer.isLoading)
    }
}
