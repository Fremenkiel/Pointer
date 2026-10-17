import Foundation

/// A stable, globally unique ID of one kind of entity (D-17). Never reused, never changed.
public protocol EntityIdentifier: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// The UUID of the entity.
    var rawValue: UUID { get }

    /// Makes an ID from a UUID.
    init(rawValue: UUID)
}

extension EntityIdentifier {
    /// The lowercase string form of the UUID, for file names and log entries.
    public var description: String { rawValue.uuidString.lowercased() }

    /// Orders IDs by their UUID bytes. Version 7 UUIDs then sort by creation time.
    public static func < (left: Self, right: Self) -> Bool { left.rawValue < right.rawValue }
}
