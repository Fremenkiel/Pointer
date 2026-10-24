import Dispatch
import Geometry
import Model
import os

/// The text boxes of the canvas on the render thread, with their layouts and a spatial grid
/// (architecture.md 5.4 and 5.6).
final class TextStore {
    /// One text box with its layout.
    struct Entry {
        /// The top-left corner in canvas space.
        let origin: Point
        /// The text of the layout. It shares the storage of the text of the box.
        let text: String
        /// The layout of the text.
        let layout: TextLayout
        /// The bounds in canvas space, with a margin for the glyphs that leave the line box.
        let bounds: Rect
    }

    /// The part of a line height that glyphs can reach outside the box, for accents and
    /// fallback glyphs.
    static let boundsMargin = 0.5

    private(set) var entries: [TextBoxID: Entry] = [:]
    /// The grid of the text boxes, with the cell size of the strokes (architecture.md 5.6).
    private(set) var grid = SpatialGrid<TextBoxID>(
        cellSize: StrokeStore.gridCellSize,
        maxCellsPerItem: Limits.maxGridCellsPerItem
    )

    /// The number of text boxes.
    var count: Int { entries.count }

    /// The fewest boxes of one thread in a load.
    static let minimumChunk = 64
    /// The most threads of a load. The iPad Pro (M4) has 4 performance cores.
    static let maxChunks = 8

    /// A text box with its layout, made off the render thread at a load (D-92).
    struct LaidOut: Sendable {
        let box: TextBox
        let layout: TextLayout
    }

    /// Lays out the text boxes of a load in chunks on several threads, because the 5,000 boxes of
    /// D-56 took 62 ms on one thread (task 2.3 of docs/m5-plan.md). It runs off the render
    /// thread, so the first frame does not wait for it (D-92).
    ///
    /// - Precondition: The boxes are at most `Limits.maxNodesPerCanvas`.
    static func layOut(_ boxes: [TextBox]) -> [LaidOut] {
        precondition(boxes.count <= Limits.maxNodesPerCanvas, "Too many text boxes")
        let layouts = inChunks(boxes) { TextLayout(text: $0.text) }
        assert(layouts.count == boxes.count, "Each box has its layout")
        return zip(boxes, layouts).map { LaidOut(box: $0, layout: $1) }
    }

    /// Runs `transform` on each item in up to `maxChunks` chunks on several threads, and returns
    /// the results in the order of the items. The text boxes and the card titles of a load use
    /// it (D-92).
    ///
    /// - Precondition: The items are at most `Limits.maxNodesPerCanvas`.
    static func inChunks<Item: Sendable, Result: Sendable>(
        _ items: [Item],
        _ transform: @Sendable (Item) -> Result
    ) -> [Result] {
        precondition(items.count <= Limits.maxNodesPerCanvas, "Too many items in one load")
        let chunkCount = min(max(items.count / minimumChunk, 1), maxChunks)
        let chunkSize = (items.count + chunkCount - 1) / chunkCount
        assert(chunkCount * chunkSize >= items.count, "The chunks cover each item")
        let results = OSAllocatedUnfairLock(
            initialState: [[Result]](repeating: [], count: chunkCount)
        )
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let range =
                min(chunk * chunkSize, items.count)..<min((chunk + 1) * chunkSize, items.count)
            let local = items[range].map(transform)
            results.withLock { $0[chunk] = local }
        }
        let all = results.withLock { $0 }.flatMap { $0 }
        assert(all.count == items.count, "Each item has its result")
        return all
    }

    /// Adds a text box, or replaces the box with the same ID, and lays out its text. A box with
    /// the text of the box that it replaces keeps that layout, so that each drag step of a move
    /// skips Core Text (review of M5).
    ///
    /// - Returns: The bounds of the box before the change, or `nil` for a new box.
    @discardableResult  // A load needs no old bounds.
    func add(_ box: TextBox) -> Rect? {
        precondition(box.origin.isFinite, "Text box \(box.id) has an origin that is not finite")
        if let earlier = entries[box.id], earlier.text == box.text {
            return insert(box, layout: earlier.layout)
        }
        return insert(box, layout: TextLayout(text: box.text))
    }

    /// Adds a box with its layout, or replaces the box with the same ID.
    ///
    /// - Returns: The bounds of the box before the change, or `nil` for a new box.
    @discardableResult  // A load needs no old bounds.
    func insert(_ box: TextBox, layout: TextLayout) -> Rect? {
        let earlier = remove(box.id)
        let margin = TextLayout.lineHeight * Self.boundsMargin
        let bounds = Rect(origin: box.origin, size: layout.size).expanded(by: margin)
        entries[box.id] = Entry(origin: box.origin, text: box.text, layout: layout, bounds: bounds)
        grid.insert(box.id, bounds: bounds)
        assert(grid.count == entries.count, "The grid holds each text box")
        return earlier
    }

    /// Removes a text box.
    ///
    /// - Returns: The bounds of the removed box, or `nil` if the store does not hold it.
    @discardableResult  // A replace needs no bounds of a box that was not there.
    func remove(_ id: TextBoxID) -> Rect? {
        guard let entry = entries.removeValue(forKey: id) else { return nil }
        let wasInGrid = grid.remove(id)
        assert(wasInGrid, "Text box \(id) was in the grid")
        assert(grid.count == entries.count, "The grid holds each text box")
        return entry.bounds
    }
}
