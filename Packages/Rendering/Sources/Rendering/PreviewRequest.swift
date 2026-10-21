import Geometry
import Model

/// One request of a card preview from the render thread to the loader (D-97).
struct PreviewRequest: Sendable {
    /// The card whose child canvas the preview shows.
    let card: CardID
    /// The bounds of the card in canvas space. The loader drops a request whose card left the
    /// texture area.
    let bounds: Rect
    /// The size step: 128, 256, or 512 pixels.
    let step: Int
}
