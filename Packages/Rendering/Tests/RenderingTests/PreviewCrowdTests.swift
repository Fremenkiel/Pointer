import CoreGraphics
import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Testing

@testable import Rendering

/// More cards on the screen than the preview atlas has slots (review after M9, section 3.2,
/// item 6). The frame loop must come to rest, not evict and load the previews for ever.
@MainActor
@Suite("A screen with more cards than preview slots")
struct PreviewCrowdTests {
    /// The cards: a grid of 2,000 cards of 64 by 48 points at zoom 0.25 on the 11-inch screen.
    private static let columns = 50
    private static let count = 2_000

    private static func cards() throws -> [Card] {
        try (0..<count).map { index in
            let origin = Point(
                x: -2_600 + Double(index % columns) * 104,
                y: -1_900 + Double(index / columns) * 90
            )
            let frame = Rect(origin: origin, size: Size(width: 64, height: 48))
            let id = CardID(
                rawValue: UUID(
                    uuid: (
                        6, UInt8(index & 255), UInt8(index >> 8), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0
                    )
                )
            )
            return try Card(
                id: id,
                meta: RecordMeta(created: Self.created),
                canvasID: CanvasID(rawValue: UUID()),
                frame: frame,
                title: nil,
                sortKey: FractionalIndex(rawValue: "V")
            )
        }
    }

    private static let created = HybridTimestamp(
        wallMillis: 1,
        counter: 0,
        device: DeviceID(rawValue: UUID())
    )

    @Test("2,000 cards at zoom 0.25 come to rest with their previews")
    func crowdRests() async throws {
        let source = FakePreviews(data: try FakePreviews.png(width: 128, height: 96))
        let renderer = try CanvasRenderer(previews: source)
        let layer = CAMetalLayer()
        renderer.configure(layer)
        layer.drawableSize = CGSize(width: 2_420, height: 1_668)
        renderer.setViewport(viewSize: Size(width: 1_210, height: 834), displayScale: 2)
        renderer.camera = Camera(center: .zero, zoom: Limits.minZoom)
        renderer.load(try Self.cards())
        var frames = 0
        var isBusy = true
        // 20 s of frames at most.
        for _ in 0..<2_400 where isBusy {
            isBusy = renderer.renderFrame(into: layer, deadline: nil) || renderer.isLoading
            frames += 1
            try await Task.sleep(for: .milliseconds(8))
        }
        let reads = source.readCount
        #expect(!isBusy, "The frame loop rests: \(frames) frames, \(reads) reads")
        #expect(reads <= Self.count * 2, "\(reads) reads for \(Self.count) cards")
    }
}
