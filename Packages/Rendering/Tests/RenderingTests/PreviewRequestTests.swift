import CoreGraphics
import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Synchronization
import Testing

@testable import Rendering

/// A preview source that has no data for its first `failures` reads, and the image after them.
final class FlakyPreviews: PreviewSource {
    let data: Data
    let failures: Int
    private let reads = Mutex(0)

    init(data: Data, failures: Int) {
        self.data = data
        self.failures = failures
    }

    /// The number of reads so far.
    var readCount: Int { reads.withLock { $0 } }

    func preview(of canvas: CanvasID, cardAspect: Double) async -> Data? {
        let read = reads.withLock { count -> Int in
            count += 1
            return count
        }
        return read > failures ? data : nil
    }
}

/// The requests of the card previews and the retry of the committed layer (review after M8,
/// section 3.2, item 5, and review after M9, section 3.2, items 5 and 7).
@MainActor
@Suite("Preview requests")
struct PreviewRequestTests {
    private static func layer(for renderer: CanvasRenderer) -> CAMetalLayer {
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 400, height: 240)
        renderer.setViewport(viewSize: Size(width: 200, height: 120), displayScale: 2)
        return layer
    }

    /// `count` cards of 64 by 48 points in rows of 6, all on the screen at zoom 0.25.
    private static func cards(_ count: Int) throws -> [Card] {
        try (0..<count).map { index in
            let origin = Point(x: -380 + Double(index % 6) * 120, y: -200 + Double(index / 6) * 80)
            let frame = Rect(origin: origin, size: Size(width: 64, height: 48))
            return try CardStoreTests.card(UInt8(index + 1), frame: frame, title: nil)
        }
    }

    /// Draws frames until the renderer rests and loads nothing, at most 4 s.
    private static func settle(_ renderer: CanvasRenderer, layer: CAMetalLayer) async throws {
        for _ in 0..<4_000 {
            let isBusy = renderer.renderFrame(into: layer, deadline: nil) || renderer.isLoading
            guard isBusy else { return }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("Previews past the limit of waiting requests load without a new build")
    func pastTheLimit() async throws {
        let source = FakePreviews(data: try FakePreviews.png(width: 128, height: 96))
        let renderer = try CanvasRenderer(previews: source)
        let layer = Self.layer(for: renderer)
        renderer.camera = Camera(center: .zero, zoom: Limits.minZoom)
        let count = RendererConfiguration().previewRequestLimit + 8
        renderer.load(try Self.cards(count))
        try await Self.settle(renderer, layer: layer)
        #expect(source.readCount == count)
        let stored = renderer.engine.withRenderer { $0.previews?.entries.count ?? 0 }
        #expect(stored == count)
    }

    @Test("A screen of more previews than slots loads each preview once and rests")
    func moreCardsThanSlots() async throws {
        // 1 MB holds 4 previews of 512 pixels. 9 cards of 600 pixels on the screen want that
        // step. The old code evicted a shown preview for each new one, and the redraw of the
        // evicted card asked for it again, so the screen never rested (D-193).
        var configuration = RendererConfiguration()
        configuration.previewAtlasByteBudget = 1 << 20
        let source = FakePreviews(data: try FakePreviews.png(width: 512, height: 340))
        let renderer = try CanvasRenderer(configuration: configuration, previews: source)
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 2_000, height: 1_400)
        renderer.setViewport(viewSize: Size(width: 1_000, height: 700), displayScale: 2)
        renderer.camera = Camera(center: .zero, zoom: Limits.standardZoom)
        let cards = try (0..<9).map { index in
            let origin = Point(x: -480 + Double(index % 3) * 320, y: -330 + Double(index / 3) * 220)
            let frame = Rect(origin: origin, size: Size(width: 300, height: 200))
            return try CardStoreTests.card(UInt8(index + 1), frame: frame, title: nil)
        }
        renderer.load(cards)
        try await Self.settle(renderer, layer: layer)
        #expect(!renderer.isLoading, "The screen rests")
        #expect(source.readCount == cards.count, "Each preview loads once")
        let stored = renderer.engine.withRenderer { $0.previews?.entries.count ?? 0 }
        #expect(stored == 4, "The atlas holds its 4 slots")
    }

    @Test("A card asks again for its preview after a source without data")
    func againAfterNoData() async throws {
        let source = FlakyPreviews(data: try FakePreviews.png(width: 128, height: 96), failures: 1)
        let renderer = try CanvasRenderer(previews: source)
        let layer = Self.layer(for: renderer)
        renderer.camera = Camera(center: .zero, zoom: Limits.minZoom)
        renderer.load(try Self.cards(1))
        try await Self.settle(renderer, layer: layer)
        #expect(source.readCount == 1)
        // A move of the camera starts a build, which asks for the missing preview again.
        renderer.camera = Camera(center: Point(x: 10, y: 0), zoom: Limits.minZoom)
        try await Self.settle(renderer, layer: layer)
        #expect(source.readCount == 2)
        let stored = renderer.engine.withRenderer { $0.previews?.entries.count ?? 0 }
        #expect(stored == 1)
    }

    @Test("A committed layer that fails waits before its next try")
    func layerRetry() throws {
        let renderer = try CanvasRenderer()
        let size = CGSize(width: 400, height: 240)
        let attempts = renderer.engine.withRenderer { frames -> [Int] in
            frames.beforeLayer = { () throws(RenderingError) in
                throw .resourceUnavailable("the test refuses the textures")
            }
            for _ in 0..<FrameRenderer.layerRetryCalls / 4 {
                _ = frames.committedLayer(for: size)
            }
            let whileFailing = frames.layerAttempts
            frames.beforeLayer = nil
            // After the wait, the next try makes the layer.
            var layer: CommittedLayer?
            for _ in 0...FrameRenderer.layerRetryCalls where layer == nil {
                layer = frames.committedLayer(for: size)
            }
            return [whileFailing, frames.layerAttempts, layer == nil ? 0 : 1]
        }
        #expect(attempts == [1, 2, 1])
    }

    @Test("Each frame of an open marks the preview slot of the opened card as used")
    func openMarksSlot() async throws {
        let source = FakePreviews(data: try FakePreviews.png(width: 128, height: 96))
        let renderer = try CanvasRenderer(previews: source)
        let layer = Self.layer(for: renderer)
        let card = try Self.cards(1)[0]
        renderer.camera = Camera(center: card.frame.center, zoom: 1)
        renderer.load([card])
        try await Self.settle(renderer, layer: layer)
        renderer.beginOpen(of: card.id)
        for _ in 0..<5 {
            _ = renderer.renderFrame(into: layer, deadline: nil)
        }
        let uses = renderer.engine.withRenderer { frames -> [UInt64] in
            guard let previews = frames.previews, let entry = previews.entries[card.id] else {
                return []
            }
            return [previews.slots.lastUse(of: entry.slot), frames.frame]
        }
        #expect(uses.count == 2 && uses.first == uses.last, "Last use and frame: \(uses)")
    }
}
