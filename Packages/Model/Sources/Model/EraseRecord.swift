/// The mark that a stroke is erased (data-model.md section 7.5, D-30).
///
/// An undo of the erase sets `isDeleted`. No erase record is ever removed from the library.
public struct EraseRecord: Hashable, Sendable {
    /// The erased stroke.
    public let strokeID: StrokeID
    /// The clock value of the erase.
    public let erased: HybridTimestamp
    /// The clock value of the last change.
    public let modified: HybridTimestamp
    /// True after an undo of the erase.
    public let isDeleted: Bool

    /// Makes an erase record.
    public init(
        strokeID: StrokeID,
        erased: HybridTimestamp,
        modified: HybridTimestamp,
        isDeleted: Bool
    ) {
        self.strokeID = strokeID
        self.erased = erased
        self.modified = modified
        self.isDeleted = isDeleted
    }
}
