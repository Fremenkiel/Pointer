import Geometry
import Metal
import Model

/// The decoded card previews on the GPU: one `.r8Unorm` texture with slots of 512, 256, and 128
/// pixels (m6-plan.md section 4, rule 2, D-97). No preview makes a texture of its own.
///
/// The render thread owns it. It also keeps the requests of the previews that are missing or
/// too small, at most `requestLimit` at a time.
final class PreviewAtlas {
    /// The size steps of a preview, in pixels (D-97).
    static let steps = [128, 256, 512]
    /// The width of the atlas: 4 blocks of 512 pixels.
    static let width = 2_048

    /// One preview in the atlas.
    struct Entry {
        let slot: PreviewSlots.Slot
        /// The top-left pixel of the preview in the atlas.
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        /// The size step of the preview.
        let step: Int
    }

    /// The atlas texture.
    let texture: any MTLTexture
    /// The requests that wait for the loader or for their result, at most this many.
    let requestLimit: Int
    private(set) var slots: PreviewSlots
    private(set) var entries: [CardID: Entry] = [:]
    /// The cards whose request waits for its result.
    private(set) var requested: Set<CardID> = []
    /// The cards without a valid preview file. They ask again only after a change.
    private(set) var unavailable: Set<CardID> = []
    /// The new requests of the current frame. Reused (PERF-01).
    var wanted: [PreviewRequest] = []
    /// The results that wait for an upload, oldest first.
    var pending: [DecodedPreview] = []
    /// The canvas area of the cards whose new previews wait for a green redraw. It waits while a
    /// build runs: a green change restarts the green part of a build, and previews arrive for
    /// seconds at zoom 0.25, so no build would complete (m6-plan.md task 3.6).
    var dirtyArea: Rect?
    /// The staging buffers of the uploads.
    let uploads: PreviewUploads
    /// The cards whose slots went in the last store. Reused.
    private var evicted: [CardID] = []

    /// Makes the atlas.
    ///
    /// - Precondition: `byteBudget` is a positive multiple of 1 MB, and `requestLimit` is
    ///   positive.
    /// - Throws: `RenderingError.resourceUnavailable` if Metal cannot make the texture.
    init(resources: InkResources, byteBudget: Int, requestLimit: Int) throws(RenderingError) {
        let rowBytes = Self.width * PreviewSlots.sides[0]
        precondition(byteBudget > 0 && byteBudget.isMultiple(of: rowBytes), "Budget \(byteBudget)")
        precondition(requestLimit > 0, "A request limit is positive, got \(requestLimit)")
        let columns = Self.width / PreviewSlots.sides[0]
        let rows = byteBudget / rowBytes
        texture = try resources.makeTarget(
            width: Self.width,
            height: rows * PreviewSlots.sides[0],
            format: .r8Unorm
        )
        slots = PreviewSlots(blockCount: rows * columns, columns: columns)
        uploads = try PreviewUploads(device: resources.device)
        self.requestLimit = requestLimit
        entries.reserveCapacity(slots.slotCount)
        requested.reserveCapacity(requestLimit)
        wanted.reserveCapacity(requestLimit)
        pending.reserveCapacity(requestLimit)
        evicted.reserveCapacity(slots.slotCount)
    }

    /// Returns the size step of a card of `pixels` pixels on its longer side: the smallest step
    /// that holds it, or the largest step.
    static func step(forPixels pixels: Double) -> Int {
        precondition(pixels >= 0 && pixels.isFinite, "A card has a size, got \(pixels)")
        return steps.first { Double($0) >= pixels } ?? steps[steps.count - 1]
    }

    /// Asks for the preview of a card in the step `step`, unless a request of it waits, the card
    /// has no preview file, or the limit of waiting requests is reached.
    func want(_ card: CardID, bounds: Rect, step: Int, cardAspect: Double) {
        precondition(Self.steps.contains(step), "Step \(step) is not a preview size")
        guard !requested.contains(card), !unavailable.contains(card),
            requested.count < requestLimit
        else { return }
        requested.insert(card)
        wanted.append(
            PreviewRequest(card: card, bounds: bounds, step: step, cardAspect: cardAspect)
        )
        assert(requested.count <= requestLimit, "At most \(requestLimit) requests wait")
    }

    /// Takes the result of a request. Pixels get a slot of the size of their step, and the slot
    /// of an earlier preview of the card goes.
    ///
    /// - Returns: The entry to fill with the pixels, or `nil` if no slot is free in this frame.
    ///   `evictedCards` gets the cards whose previews went.
    func store(_ preview: DecodedPreview, frame: UInt64, evictedCards: inout [CardID]) -> Entry? {
        precondition(Self.steps.contains(preview.step), "Step \(preview.step) is no preview size")
        requested.remove(preview.card)
        switch preview.outcome {
        case .dropped:
            return nil
        case .unavailable:
            unavailable.insert(preview.card)
            return nil
        case .pixels(let pixels):
            precondition(pixels.count == preview.width * preview.height, "Pixels of the size")
            return place(preview, frame: frame, evictedCards: &evictedCards)
        }
    }

    /// Notes that a frame drew the preview of `card`.
    func markUsed(_ entry: Entry, frame: UInt64) {
        slots.markUsed(entry.slot, frame: frame)
    }

    /// Removes the preview of a card that left the canvas, and lets it ask again later.
    func forget(_ card: CardID) {
        assert(!requested.contains(card) || entries[card] == nil, "A requested card has no entry")
        unavailable.remove(card)
        guard let entry = entries.removeValue(forKey: card) else { return }
        slots.free(entry.slot)
        assert(entries[card] == nil, "The card left the atlas")
    }

    private func place(
        _ preview: DecodedPreview,
        frame: UInt64,
        evictedCards: inout [CardID]
    ) -> Entry? {
        precondition(preview.width <= preview.step && preview.height <= preview.step, "Size")
        if let earlier = entries.removeValue(forKey: preview.card) {
            slots.free(earlier.slot)
        }
        guard let level = PreviewSlots.sides.firstIndex(of: preview.step) else {
            preconditionFailure("Step \(preview.step) is not a slot side")
        }
        evicted.removeAll(keepingCapacity: true)
        let slot = slots.allocate(level: level, for: preview.card, frame: frame, evicted: &evicted)
        for card in evicted {
            entries.removeValue(forKey: card)
            evictedCards.append(card)
        }
        guard let slot else { return nil }
        let origin = slots.origin(of: slot)
        let entry = Entry(
            slot: slot,
            x: origin.x,
            y: origin.y,
            width: preview.width,
            height: preview.height,
            step: preview.step
        )
        entries[preview.card] = entry
        return entry
    }
}
