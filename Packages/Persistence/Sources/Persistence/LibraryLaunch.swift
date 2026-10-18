import Model

/// What the app needs from the library at launch (storage.md section 5).
public struct LibraryLaunch: Equatable, Sendable {
    /// True if the library has a newer schema than the app knows. The app shows a message.
    public let isReadOnly: Bool
    /// The largest clock value of the library. The clock continues after it (review A-18).
    public let lastTimestamp: HybridTimestamp?
}
