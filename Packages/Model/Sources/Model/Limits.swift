/// All limits of Pointer (architecture.md section 10). Code uses the names, never the numbers.
public enum Limits {
    /// The depth of the card tree (CARD-09).
    public static let maxDepth = 32
    /// Control points per stroke, about 68 s at 240 Hz. A longer path becomes several strokes.
    public static let maxPointsPerStroke = 16_384
    /// Strokes per canvas. The upper bound for loops and memory.
    public static let maxStrokesPerCanvas = 200_000
    /// Cards plus text boxes per canvas.
    public static let maxNodesPerCanvas = 10_000
    /// Characters per text box.
    public static let maxTextLength = 100_000
    /// Workspaces in the library.
    public static let maxWorkspaces = 1_000
    /// Undo steps per canvas.
    public static let maxHistoryDepth = 500
    /// The smallest camera zoom (CAN-04).
    public static let minZoom = 0.25
    /// The largest camera zoom (CAN-04).
    public static let maxZoom = 8.0
    /// The standard camera zoom (CAN-04).
    public static let standardZoom = 1.0
    /// The number of control points that two neighbor strokes of one long path share, so that the
    /// curve continues without a gap (architecture.md 4.2).
    public static let strokeOverlapPoints = 3

    /// The allowed camera zoom range.
    public static var zoomRange: ClosedRange<Double> { minZoom...maxZoom }
}
