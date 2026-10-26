import Model

/// The result of one preview request, from the loader to the render thread.
struct DecodedPreview: Sendable {
    /// What the loader found.
    enum Outcome: Sendable {
        /// The gray pixels of the preview, row by row, `width` by `height`.
        case pixels([UInt8])
        /// No file, or a file that does not decode. The card shows its border and title only.
        case unavailable
        /// The card left the texture area before the decode, so the loader skipped it.
        case dropped
    }

    /// The card of the preview.
    let card: CardID
    /// The size step of the request: 64, 128, 256, or 512 pixels.
    let step: Int
    /// The width in pixels, at most `step`.
    let width: Int
    /// The height in pixels, at most `step`.
    let height: Int
    /// What the loader found.
    let outcome: Outcome
}
