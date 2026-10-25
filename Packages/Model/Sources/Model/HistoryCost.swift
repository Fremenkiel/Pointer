/// The memory that a step of the undo history holds, in bytes (D-183). The budget of the history
/// counts bytes, because a count of points held 67 MB as strokes of 300 points and 433 MB as
/// strokes of 2 points.
public enum HistoryCost {
    /// The bytes of a stroke per control point, from a measure on the Mac in a release build.
    static let bytesPerPoint = 17
    /// The fixed bytes of a stroke or a text: the value, its storage header, and the rounding of
    /// the heap.
    static let bytesPerItem = 192

    /// Returns the bytes of a stroke of `pointCount` control points: 226 bytes for 2 points and
    /// 5,292 for 300, within 3 % of the measure of D-183.
    ///
    /// - Precondition: `pointCount` is positive.
    public static func bytes(ofStroke pointCount: Int) -> Int {
        precondition(pointCount > 0, "A stroke has points, got \(pointCount)")
        return bytesPerPoint * pointCount + bytesPerItem
    }

    /// Returns the bytes of a text: its UTF-8 bytes and the fixed bytes of an item. A text box
    /// of 200 ASCII characters measured 400 bytes, and one of 10,000 CJK characters 32,931.
    public static func bytes(ofText text: String?) -> Int {
        (text?.utf8.count ?? 0) + bytesPerItem
    }
}
