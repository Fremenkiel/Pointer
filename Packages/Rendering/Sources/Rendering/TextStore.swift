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
    private(set) var grid = SpatialGrid<TextBoxID>(cellSize: StrokeStore.gridCellSize)

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
        let chunkCount = min(max(boxes.count / minimumChunk, 1), maxChunks)
        let chunkSize = (boxes.count + chunkCount - 1) / chunkCount
        assert(chunkCount * chunkSize >= boxes.count, "The chunks cover each box")
        let results = OSAllocatedUnfairLock(
            initialState: [[TextLayout]](repeating: [], count: chunkCount)
        )
        DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
            let range =
                min(chunk * chunkSize, boxes.count)..<min((chunk + 1) * chunkSize, boxes.count)
            let local = boxes[range].map { TextLayout(text: $0.text) }
            results.withLock { $0[chunk] = local }
        }
        let layouts = results.withLock { $0 }.flatMap { $0 }
        assert(layouts.count == boxes.count, "Each box has its layout")
        return zip(boxes, layouts).map { LaidOut(box: $0, layout: $1) }
    }

    /// Adds a text box, or replaces the box with the same ID, and lays out its text.
    ///
    /// - Returns: The bounds of the box before the change, or `nil` for a new box.
    @discardableResult  // A load needs no old bounds.
    func add(_ box: TextBox) -> Rect? {
        precondition(box.origin.isFinite, "Text box \(box.id) has an origin that is not finite")
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
        entries[box.id] = Entry(origin: box.origin, layout: layout, bounds: bounds)
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
