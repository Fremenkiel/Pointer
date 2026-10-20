/// The clock values and the tombstone flag of a stored record (data-model.md section 5).
public struct RecordMeta: Hashable, Sendable {
    /// The clock value at creation.
    public let created: HybridTimestamp
    /// The clock value of the last change.
    public let modified: HybridTimestamp
    /// True if the record is a tombstone.
    public let isDeleted: Bool

    /// Makes the fields of a record.
    public init(created: HybridTimestamp, modified: HybridTimestamp, isDeleted: Bool) {
        self.created = created
        self.modified = modified
        self.isDeleted = isDeleted
    }

    /// Makes the fields of a new record that was created and last changed at `created`.
    public init(created: HybridTimestamp) {
        self.init(created: created, modified: created, isDeleted: false)
    }

    /// Returns the fields after a change at `time`: the same creation, the new change time, and
    /// the tombstone flag `isDeleted`, or the flag as it is.
    public func changed(at time: HybridTimestamp, isDeleted: Bool? = nil) -> RecordMeta {
        RecordMeta(created: created, modified: time, isDeleted: isDeleted ?? self.isDeleted)
    }
}
