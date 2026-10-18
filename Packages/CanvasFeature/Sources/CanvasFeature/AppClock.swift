import Model

/// The one clock of the app: the clock values and the IDs of all new records (data-model.md 3
/// and 4).
///
/// The canvas and the workspace selector share it, so that the clock values of this iPad grow
/// across all records. `PointerApp` makes it from the `lastTimestamp` of the library and the
/// `DeviceID` of the device state.
@MainActor
public final class AppClock {
    /// The source of the IDs and the clock values of new strokes.
    public var factory: StrokeFactory

    /// Makes the clock.
    public init(factory: StrokeFactory) {
        self.factory = factory
    }

    /// Returns a new clock value that is greater than each value before it.
    public func now() -> HybridTimestamp {
        factory.clock.now()
    }

    /// Returns a new ID of any entity type.
    public func makeIdentifier<ID: EntityIdentifier>(_ type: ID.Type = ID.self) -> ID {
        factory.identifiers.make(type)
    }
}
