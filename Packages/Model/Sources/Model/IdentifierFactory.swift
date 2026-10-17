/// Makes new entity IDs as UUID version 7 from an injected clock and random source (D-31).
public struct IdentifierFactory {
    private let wallClock: any WallClock
    private var random: any RandomNumberGenerator

    /// Makes a factory.
    public init(wallClock: any WallClock, random: any RandomNumberGenerator) {
        self.wallClock = wallClock
        self.random = random
    }

    /// Returns a new ID of any entity type. A time beyond 48 bits uses the largest time.
    public mutating func make<ID: EntityIdentifier>(_ type: ID.Type = ID.self) -> ID {
        let millis = min(wallClock.nowMillis(), UUIDVersion7.maxMillis)
        return ID(rawValue: UUIDVersion7.make(millis: millis, random: &random))
    }
}
