import Geometry
import Metal
import Model
import Testing

@testable import Rendering

/// The slot of a card whose larger preview finds no room (review of 2026-10-28, 3.2.9).
@MainActor
@Suite("Preview slot of a card that grows")
struct PreviewSlotKeepTests {
    private static func card(_ index: Int) -> CardID {
        CardID(rawValue: UUID(uuid: (8, UInt8(index), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    private static func preview(_ card: CardID, step: Int) -> DecodedPreview {
        DecodedPreview(
            card: card,
            step: step,
            width: step,
            height: step,
            outcome: .pixels([UInt8](repeating: 0, count: step * step))
        )
    }

    @Test("If no slot can go, a card with a smaller preview keeps it")
    func keepsSmallerPreview() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let resources = try InkResources(device: device)
        // The smallest atlas: 4 blocks of 512 pixels, 16 slots of 256.
        let atlas = try PreviewAtlas(resources: resources, byteBudget: 1 << 20, requestLimit: 16)
        let shown = { (_: CardID) in true }
        for index in 1...15 {
            #expect(
                atlas.store(Self.preview(Self.card(index), step: 256), frame: 1, isShown: shown)
                    != nil
            )
        }
        let grower = Self.card(16)
        #expect(atlas.store(Self.preview(grower, step: 128), frame: 1, isShown: shown) != nil)
        for index in 17...19 {
            #expect(
                atlas.store(Self.preview(Self.card(index), step: 128), frame: 1, isShown: shown)
                    != nil
            )
        }
        #expect(atlas.entries[grower]?.step == 128)
        // Each slot holds the preview of a card on the screen, so none can go (D-193).
        let larger = atlas.store(Self.preview(grower, step: 256), frame: 2, isShown: shown)
        #expect(larger == nil)
        #expect(atlas.entries[grower]?.step == 128, "The smaller preview stays")
        #expect(atlas.noRoom.contains(grower))
    }
}
