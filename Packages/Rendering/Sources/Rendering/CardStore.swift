import Geometry
import Model

/// The cards of the canvas on the render thread, with their title layouts and a spatial grid
/// (architecture.md 5.5 and 5.6).
final class CardStore {
    /// One card with the layout of its title.
    struct Entry {
        /// The frame in canvas space.
        let frame: Rect
        /// The title of the layout, or `nil` for a card without a title.
        let title: String?
        /// The layout of the title, or `nil` for a card without a title.
        let layout: TextLayout?
        /// The bounds in canvas space: the frame and the title above it, with a margin for the
        /// border and for the glyphs that leave the line box.
        let bounds: Rect

        /// The top-left corner of the title: the last line of the title sits on the top edge of
        /// the frame.
        var titleOrigin: Point? {
            guard let layout else { return nil }
            return Point(x: frame.minX, y: frame.minY - layout.size.height)
        }
    }

    /// A card with the layout of its title, made off the render thread at a load (D-92).
    struct LaidOut: Sendable {
        let card: Card
        let layout: TextLayout?
    }

    private(set) var entries: [CardID: Entry] = [:]
    /// The grid of the cards, with the cell size of the strokes (architecture.md 5.6).
    private(set) var grid = SpatialGrid<CardID>(
        cellSize: StrokeStore.gridCellSize,
        maxCellsPerItem: Limits.maxGridCellsPerItem
    )

    /// The loads whose title layouts still run off the render thread (D-92).
    var loadsInFlight = 0
    /// The cards that an edit changed while a load was in flight. The load skips them, because
    /// the edit is newer.
    var editedDuringLoad: Set<CardID> = []

    /// The number of cards.
    var count: Int { entries.count }

    /// Lays out the titles of the cards of a load in the chunks of the text load, off the render
    /// thread (D-92).
    ///
    /// - Precondition: The cards are at most `Limits.maxNodesPerCanvas`.
    static func layOut(_ cards: [Card]) -> [LaidOut] {
        precondition(cards.count <= Limits.maxNodesPerCanvas, "Too many cards")
        let layouts = TextStore.inChunks(cards) { card in titleLayout(of: card.title) }
        assert(layouts.count == cards.count, "Each card has its title layout")
        return zip(cards, layouts).map { LaidOut(card: $0, layout: $1) }
    }

    /// Returns the layout of a title, or `nil` for no title or an empty title.
    static func titleLayout(of title: String?) -> TextLayout? {
        guard let title, !title.isEmpty else { return nil }
        precondition(
            title.unicodeScalars.count <= Limits.maxTitleLength,
            "A title holds at most \(Limits.maxTitleLength) code points"
        )
        let layout = TextLayout(text: title)
        assert(layout.lineCount >= 1, "A title has at least one line")
        return layout
    }

    /// Reserves room for the cards of a load, once per load (PERF-01).
    ///
    /// - Precondition: `count` is at most `Limits.maxNodesPerCanvas`.
    func reserveCapacity(_ count: Int) {
        precondition(
            count >= 0 && count <= Limits.maxNodesPerCanvas,
            "A store reserves 0 to \(Limits.maxNodesPerCanvas) cards, got \(count)"
        )
        entries.reserveCapacity(count)
        grid.reserveCapacity(count)
        assert(entries.capacity >= count, "The store holds room for \(count) cards")
    }

    /// Adds a card, or replaces the card with the same ID, and lays out its title. A card with
    /// the title of the card that it replaces keeps that layout, so that each drag step of a move
    /// skips Core Text, as `TextStore.add(_:)` does.
    ///
    /// - Returns: The bounds of the card before the change, or `nil` for a new card.
    @discardableResult  // A load needs no old bounds.
    func add(_ card: Card) -> Rect? {
        precondition(card.frame.origin.isFinite, "Card \(card.id) has a frame that is not finite")
        assert(card.frame.size.width >= Limits.minCardWidth, "Card \(card.id) is too narrow")
        if let earlier = entries[card.id], earlier.title == card.title {
            return insert(card, layout: earlier.layout)
        }
        return insert(card, layout: Self.titleLayout(of: card.title))
    }

    /// Adds a card with the layout of its title, or replaces the card with the same ID.
    ///
    /// - Returns: The bounds of the card before the change, or `nil` for a new card.
    @discardableResult  // A load needs no old bounds.
    func insert(_ card: Card, layout: TextLayout?) -> Rect? {
        precondition(card.frame.origin.isFinite, "Card \(card.id) has a frame that is not finite")
        let earlier = remove(card.id)
        var bounds = card.frame
        if let layout {
            let title = Rect(
                origin: Point(x: card.frame.minX, y: card.frame.minY - layout.size.height),
                size: layout.size
            )
            bounds = Rect(
                minX: min(bounds.minX, title.minX),
                minY: title.minY,
                maxX: max(bounds.maxX, title.maxX),
                maxY: bounds.maxY
            )
        }
        bounds = bounds.expanded(by: TextLayout.lineHeight * TextStore.boundsMargin)
        entries[card.id] = Entry(
            frame: card.frame,
            title: card.title,
            layout: layout,
            bounds: bounds
        )
        grid.insert(card.id, bounds: bounds)
        assert(grid.count == entries.count, "The grid holds each card")
        return earlier
    }

    /// Removes all cards, for the next offscreen preview (m10-plan.md task 3.4).
    func removeAll() {
        entries.removeAll(keepingCapacity: true)
        grid = SpatialGrid(cellSize: grid.cellSize, maxCellsPerItem: grid.maxCellsPerItem)
    }

    /// Removes a card.
    ///
    /// - Returns: The bounds of the removed card, or `nil` if the store does not hold it.
    @discardableResult  // A replace needs no bounds of a card that was not there.
    func remove(_ id: CardID) -> Rect? {
        guard let entry = entries.removeValue(forKey: id) else { return nil }
        let wasInGrid = grid.remove(id)
        assert(wasInGrid, "Card \(id) was in the grid")
        assert(grid.count == entries.count, "The grid holds each card")
        return entry.bounds
    }
}
