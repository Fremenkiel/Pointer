/// The loading state of the engine, read under the inbox lock (review after M9, section 3.2,
/// item 1).
extension RenderEngine {
    /// `true` while a text layout of a load runs or waits for a frame (D-92).
    var isLoadingText: Bool { inbox.withLock { $0.isLoadingText } }

    /// `true` while a title layout of a card load runs or waits for a frame (D-92).
    var isLoadingCards: Bool { inbox.withLock { $0.isLoadingCards } }

    /// `true` while text, cards, or previews load, read under one lock, so that no wait on it
    /// ends between the inbox and the frame work (review after M9, section 3.2, item 1).
    var isLoading: Bool {
        inbox.withLock { $0.isLoadingText || $0.isLoadingCards || $0.isLoadingPreviews }
    }
}
