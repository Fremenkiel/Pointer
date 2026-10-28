import Foundation
import Geometry
import Metal
import Model
import QuartzCore
import Synchronization
import Testing
import UIKit

@testable import Rendering

/// A preview source whose calls wait until the test opens the gate.
final class GatedPreviews: PreviewSource {
    private let calls = Mutex(0)
    private let gate: AsyncStream<Void>
    /// Opens the gate for each call, the waiting one and the later ones.
    let open: AsyncStream<Void>.Continuation

    init() {
        (gate, open) = AsyncStream.makeStream()
    }

    /// The number of calls so far.
    var callCount: Int { calls.withLock { $0 } }

    func preview(of canvas: CanvasID, cardAspect: Double) async -> Data? {
        calls.withLock { $0 += 1 }
        var waiting = gate.makeAsyncIterator()
        _ = await waiting.next()
        return nil
    }
}

/// A preview source with one image for each canvas. It counts its reads.
final class FakePreviews: PreviewSource {
    let data: Data?
    private let reads = Mutex(0)

    init(data: Data?) {
        self.data = data
    }

    /// The number of reads so far.
    var readCount: Int { reads.withLock { $0 } }

    func preview(of canvas: CanvasID, cardAspect: Double) async -> Data? {
        reads.withLock { $0 += 1 }
        return data
    }

    /// A gray PNG of `width` by `height` pixels: black, with a white cross and a white frame.
    static func png(width: Int, height: Int) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: width, height: height)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 6
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: width, y: height))
            path.move(to: CGPoint(x: width, y: 0))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.append(UIBezierPath(rect: CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)))
            path.stroke()
        }
        return try #require(image.pngData())
    }
}

/// The slots, the decode, and the loader of the card previews (D-97, the M6 plan section 4).
@Suite("Card previews")
struct PreviewTests {
    private static func card(_ index: Int) -> CardID {
        CardID(
            rawValue: UUID(
                uuid: (
                    5, UInt8(index & 255), UInt8(index >> 8), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                )
            )
        )
    }

    @Test("The atlas holds its budget of 512 slots, and one more takes the oldest slot")
    func budgetPlusOne() {
        var slots = PreviewSlots(blockCount: 32, columns: 4)
        var evicted: [CardID] = []
        for index in 0..<32 {
            let slot = slots.allocate(
                level: 0,
                for: Self.card(index),
                frame: UInt64(index + 1),
                evicted: &evicted
            )
            #expect(slot != nil)
        }
        #expect(evicted.isEmpty)
        let extra = slots.allocate(level: 0, for: Self.card(99), frame: 100, evicted: &evicted)
        #expect(extra != nil)
        #expect(evicted == [Self.card(0)])
        // Each slot is in use in frame 100 now or older; a slot of this frame never goes.
        for index in 0..<32 {
            let slot = PreviewSlots.Slot(level: 0, index: index)
            if slots.owner(of: slot) != nil { slots.markUsed(slot, frame: 100) }
        }
        evicted.removeAll()
        #expect(slots.allocate(level: 0, for: Self.card(100), frame: 100, evicted: &evicted) == nil)
        #expect(evicted.isEmpty)
    }

    @Test("A block of 512 splits into four slots of 256, and those into slots of 128")
    func split() throws {
        var slots = PreviewSlots(blockCount: 2, columns: 2)
        var evicted: [CardID] = []
        var origins: [Int] = []
        for index in 0..<5 {
            let slot = try #require(
                slots.allocate(level: 1, for: Self.card(index), frame: 1, evicted: &evicted)
            )
            let origin = slots.origin(of: slot)
            origins.append(origin.x * 10_000 + origin.y)
        }
        #expect(origins == [0, 256 * 10_000, 256, 256 * 10_000 + 256, 512 * 10_000])
        let small = try #require(
            slots.allocate(level: 2, for: Self.card(9), frame: 1, evicted: &evicted)
        )
        let origin = slots.origin(of: small)
        #expect(origin.x == 512 + 256 && origin.y == 0)
        #expect(evicted.isEmpty)
    }

    @Test("A slot of 128 splits into four slots of 64 (D-193)")
    func splitToSixtyFour() throws {
        var slots = PreviewSlots(blockCount: 1, columns: 1)
        var evicted: [CardID] = []
        var origins: [Int] = []
        for index in 0..<5 {
            let slot = try #require(
                slots.allocate(level: 3, for: Self.card(index), frame: 1, evicted: &evicted)
            )
            #expect(slot.level == 3)
            let origin = slots.origin(of: slot)
            origins.append(origin.x * 10_000 + origin.y)
        }
        #expect(origins == [0, 64 * 10_000, 64, 64 * 10_000 + 64, 128 * 10_000])
        #expect(evicted.isEmpty)
    }

    @Test("The slot of a card on the screen never goes for another card (D-193)")
    func keepsTheSlotsOnTheScreen() throws {
        var slots = PreviewSlots(blockCount: 1, columns: 1)
        var evicted: [CardID] = []
        for index in 0..<4 {
            _ = try #require(
                slots.allocate(level: 1, for: Self.card(index), frame: 1, evicted: &evicted)
            )
        }
        // Cards 0 and 1 are on the screen: card 2 goes, the oldest card off the screen.
        let shown: Set<CardID> = [Self.card(0), Self.card(1)]
        let taken = slots.allocate(
            level: 1,
            for: Self.card(4),
            frame: 2,
            keeping: { shown.contains($0) },
            evicted: &evicted
        )
        #expect(taken != nil)
        #expect(evicted == [Self.card(2)])
        evicted.removeAll()
        // With each card on the screen, no slot goes.
        let refused = slots.allocate(
            level: 1,
            for: Self.card(5),
            frame: 3,
            keeping: { _ in true },
            evicted: &evicted
        )
        #expect(refused == nil)
        #expect(evicted.isEmpty)
    }

    @Test("Four free children join, so a block of 512 is free again")
    func join() throws {
        var slots = PreviewSlots(blockCount: 1, columns: 1)
        var evicted: [CardID] = []
        var taken: [PreviewSlots.Slot] = []
        for index in 0..<4 {
            taken.append(
                try #require(
                    slots.allocate(level: 1, for: Self.card(index), frame: 1, evicted: &evicted)
                )
            )
        }
        #expect(slots.allocate(level: 0, for: Self.card(8), frame: 1, evicted: &evicted) == nil)
        for slot in taken {
            slots.free(slot)
        }
        let whole = try #require(
            slots.allocate(level: 0, for: Self.card(8), frame: 2, evicted: &evicted)
        )
        let origin = slots.origin(of: whole)
        #expect(origin.x == 0 && origin.y == 0)
    }

    @Test("A gray PNG decodes to at most its step, and damaged data decodes to nothing")
    func decode() throws {
        var decoder = PreviewDecoder()
        let png = try FakePreviews.png(width: 400, height: 280)
        guard let image = decoder.decode(png, step: 256) else {
            Issue.record("The PNG does not decode")
            return
        }
        #expect(image.width == 256)
        // ImageIO rounds 280 * 256 / 400 = 179.2.
        #expect((179...180).contains(image.height))
        #expect(image.pixels.count == 256 * image.height)
        #expect(image.pixels.contains { $0 > 200 })
        #expect(decoder.decode(Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), step: 128) == nil)
        #expect(decoder.decode(Data(), step: 128) == nil)
    }

    @Test("A loader that goes serves no waiting request after the running one (review after M9)")
    func goneLoaderStops() async throws {
        let source = GatedPreviews()
        var loader: PreviewLoader? = PreviewLoader(source: source, limit: 8) { _ in }
        let area = Rect(origin: .zero, size: Size(width: 10_000, height: 10_000))
        let requests = (1...8).map { byte in
            PreviewRequest(
                card: Self.card(byte),
                bounds: Rect(origin: Point(x: 10, y: 10), size: Size(width: 64, height: 48)),
                step: 128,
                cardAspect: 4.0 / 3.0
            )
        }
        _ = loader?.request(requests, area: area)
        for _ in 0..<2_000 where source.callCount == 0 {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(source.callCount == 1)
        loader = nil
        source.open.finish()
        try await Task.sleep(for: .milliseconds(200))
        #expect(source.callCount == 1, "Each waiting request loads a whole child canvas")
    }

    @Test(
        "A preview render that the GPU did not complete throws (review after M9)",
        arguments: [MTLCommandBufferStatus.error, .notEnqueued, .committed]
    )
    func incompleteRenderThrows(status: MTLCommandBufferStatus) {
        #expect(throws: RenderingError.self) {
            try FrameRenderer.checkCompleted(status: status, error: nil)
        }
        #expect(throws: Never.self) {
            try FrameRenderer.checkCompleted(status: .completed, error: nil)
        }
    }

    @Test("The loader drops a request whose card left the texture area, before its read")
    func dropOutsideArea() async throws {
        let source = FakePreviews(data: try FakePreviews.png(width: 64, height: 48))
        let results = Mutex<[DecodedPreview]>([])
        let loader = PreviewLoader(source: source, limit: 4) { preview in
            results.withLock { $0.append(preview) }
        }
        let area = Rect(origin: .zero, size: Size(width: 100, height: 100))
        let inside = PreviewRequest(
            card: Self.card(1),
            bounds: Rect(origin: Point(x: 10, y: 10), size: Size(width: 64, height: 48)),
            step: 128,
            cardAspect: 4.0 / 3.0
        )
        let outside = PreviewRequest(
            card: Self.card(2),
            bounds: Rect(origin: Point(x: 900, y: 900), size: Size(width: 64, height: 48)),
            step: 128,
            cardAspect: 4.0 / 3.0
        )
        loader.request([outside, inside], area: area)
        for _ in 0..<2_000 where loader.isLoading || results.withLock({ $0.count }) < 2 {
            try await Task.sleep(for: .milliseconds(1))
        }
        let delivered = results.withLock { $0 }
        #expect(delivered.count == 2)
        #expect(source.readCount == 1)
        guard delivered.count == 2 else { return }
        if case .dropped = delivered[0].outcome {} else { Issue.record("The outside card is read") }
        if case .pixels(let pixels) = delivered[1].outcome {
            #expect(pixels.count == delivered[1].width * delivered[1].height)
        } else {
            Issue.record("The inside card has no pixels")
        }
    }
}
