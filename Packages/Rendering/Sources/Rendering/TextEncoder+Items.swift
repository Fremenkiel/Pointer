import Geometry
import Model

/// The items of a text pass: the room that each needs, and the path that draws its glyphs
/// (architecture.md 5.4 and 5.4.1).
extension TextEncoder {
    /// Where an item of a pass lands: the target, the atlas exponent, and the frame.
    struct Place {
        let target: InkTarget
        let exponent: Int
        let frame: UInt64
    }

    /// Returns whether the next item fits the CPU path and the stored path of the pass, or `nil`
    /// if its store does not hold it. A card writes its border and its preview on the CPU path
    /// in both cases.
    func room(for item: GreenItem) -> (cpu: Bool, stored: Bool)? {
        guard let quads = quadCount(of: item) else { return nil }
        let cards = borderQuads.count + previewQuads.count
        let extras: Int
        switch item {
        case .textBox: extras = 0
        case .card: extras = 2
        }
        let glyphs = quads - extras
        assert(glyphs >= 0, "An item has no negative glyph count")
        let cpu = quads + cards <= ring.remaining
        let storedRoom = stored.map { glyphs <= $0.remainingQuads && $0.hasRoomForRecord } ?? false
        return (cpu, storedRoom && extras + cards <= ring.remaining)
    }

    /// Returns the quads that an item writes into the glyph buffer, or `nil` if its store does
    /// not hold it: the glyphs of a box, or the border and the title glyphs of a card.
    func quadCount(of item: GreenItem) -> Int? {
        switch item {
        case .textBox(let id):
            return store.entries[id]?.layout.glyphs.count
        case .card(let id):
            guard let entry = cards.entries[id] else { return nil }
            assert((entry.layout == nil) == (entry.titleOrigin == nil), "A title has its place")
            // A border quad, a preview quad, and the title glyphs.
            return 2 + (entry.layout?.glyphs.count ?? 0)
        }
    }

    /// Writes the quads of one item into the pass.
    ///
    /// - Returns: `false` if the item fits neither path. It then stays for the next pass.
    func append(_ item: GreenItem, _ place: Place, allowsCPU: Bool) -> Bool {
        precondition(place.frame > 0, "Frames count from 1")
        switch item {
        case .textBox(let id):
            guard let entry = store.entries[id] else { return true }
            return appendText(
                entry.layout,
                of: (item, entry.version),
                at: entry.origin,
                place,
                allowsCPU: allowsCPU
            )
        case .card(let id):
            guard let entry = cards.entries[id] else { return true }
            return appendCard(id, entry: entry, place, allowsCPU: allowsCPU)
        }
    }

    /// Writes the glyphs of a layout: as a stored run, or on the CPU path if that fits.
    ///
    /// - Returns: `false` if the layout fits neither path.
    func appendText(
        _ layout: TextLayout,
        of owner: (item: GreenItem, version: UInt32),
        at origin: Point,
        _ place: Place,
        allowsCPU: Bool
    ) -> Bool {
        precondition(
            GlyphAtlas.exponentRange.contains(place.exponent),
            "Exponent \(place.exponent) is outside the atlas"
        )
        let key = GlyphRunStore.Key(item: owner.item, exponent: Int8(place.exponent))
        let outcome = appendStored(layout, key: key, version: owner.version, at: origin, place)
        switch outcome {
        case .added: return true
        case .later: return false
        case .noRoom: break
        }
        guard allowsCPU else { return false }
        append(
            layout,
            at: origin,
            target: place.target,
            exponent: place.exponent,
            frame: place.frame
        )
        return true
    }
}
