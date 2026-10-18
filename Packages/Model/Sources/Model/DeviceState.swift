/// The state of one device that is not part of the library (data-model.md 10, D-53).
///
/// The cameras are not part of it. `DeviceStateStore` reads one camera when a canvas opens.
public struct DeviceState: Hashable, Sendable {
    /// The device that makes the clock values of this app.
    public let deviceID: DeviceID
    /// The workspace that was open last, if any.
    public let lastWorkspace: WorkspaceID?
    /// The cards from the root canvas to the open canvas, at most `Limits.maxDepth`.
    public let navigationPath: [CardID]

    /// Makes a device state.
    ///
    /// - Throws: `ModelError.navigationPathTooLong` for a path above `Limits.maxDepth` cards.
    public init(
        deviceID: DeviceID,
        lastWorkspace: WorkspaceID?,
        navigationPath: [CardID]
    ) throws(ModelError) {
        guard navigationPath.count <= Limits.maxDepth else {
            throw .navigationPathTooLong(count: navigationPath.count)
        }
        self.deviceID = deviceID
        self.lastWorkspace = lastWorkspace
        self.navigationPath = navigationPath
    }
}
