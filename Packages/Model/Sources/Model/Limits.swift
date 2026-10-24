/// All limits of Pointer (architecture.md section 10). Code uses the names, never the numbers.
public enum Limits {
    /// The depth of the card tree (CARD-09).
    public static let maxDepth = 32
    /// Control points per stroke, about 68 s at 240 Hz. A longer path becomes several strokes.
    public static let maxPointsPerStroke = 16_384
    /// Strokes per canvas. The pen refuses a new stroke at this count.
    public static let maxStrokesPerCanvas = 200_000
    /// Strokes per canvas after an erase. Only the parts of an erase pass `maxStrokesPerCanvas`
    /// (D-71). The upper bound for loops and memory (D-73).
    public static let maxStrokesAfterErase = 210_000
    /// Cards plus text boxes per canvas.
    public static let maxNodesPerCanvas = 10_000
    /// Unicode code points per text box (D-29, D-57).
    public static let maxTextLength = 10_000
    /// Workspaces in the library.
    public static let maxWorkspaces = 1_000
    /// Unicode code points in a workspace title or a card title (D-57).
    public static let maxTitleLength = 120
    /// Characters of a sort key. A longer key needs a rebalance (data-model.md section 6).
    public static let maxSortKeyLength = 64
    /// The smallest card width in canvas points (data-model.md section 7.2).
    public static let minCardWidth = 64.0
    /// The smallest card height in canvas points (data-model.md section 7.2).
    public static let minCardHeight = 48.0
    /// Undo steps per canvas.
    public static let maxHistoryDepth = 500
    /// The control points that the undo history of one canvas holds, about 67 MB (D-76).
    public static let maxHistoryPointsPerCanvas = 4_000_000
    /// The control points that the histories of all sessions hold, about 270 MB (D-76).
    public static let maxHistoryPointsInSessions = 16_000_000
    /// The smallest camera zoom (CAN-04).
    public static let minZoom = 0.25
    /// The largest camera zoom (CAN-04).
    public static let maxZoom = 8.0
    /// The standard camera zoom (CAN-04).
    public static let standardZoom = 1.0
    /// The number of control points that two neighbor strokes of one long path share, so that the
    /// curve continues without a gap (architecture.md 4.2).
    public static let strokeOverlapPoints = 3

    /// The side length of a cell of the grids of the strokes, the text boxes, and the cards of a
    /// canvas, in canvas points (architecture.md 5.6).
    public static let gridCellSize = 512.0
    /// The most cells of `gridCellSize` that one item of a canvas can touch. It bounds the loops
    /// of the grids, and a load refuses a larger item as a damaged row (FLOW-03, D-158).
    ///
    /// The largest items that the app can make:
    /// - A text box of `maxTextLength` line breaks: 10,001 lines of 20.02 points (SF Mono at
    ///   17 points, measured on the Mac), about 200,200 points high, at most 393 rows. At
    ///   `TextStyle.maxWidth` (640 points), at most 3 columns: at most 1,179 cells.
    /// - A stroke of `maxPointsPerStroke` points drawn across the 13-inch screen (1,376 by
    ///   1,032 points) at `minZoom`: 5,504 by 4,128 canvas points, at most 12 by 10 cells.
    /// - A card of `Card.defaultSize` (320 by 224 points), which keeps its size (D-102): 4 cells.
    ///
    /// The bound is about 3.5 times the text box. An insert of 4,096 cells takes microseconds.
    /// An item 10,000,000 points wide touched 381 million cells and took 96 s on the Mac
    /// (review of 2026-10-24, section 3.1, item 2).
    public static let maxGridCellsPerItem = 4_096

    /// The allowed camera zoom range.
    public static var zoomRange: ClosedRange<Double> { minZoom...maxZoom }
}
