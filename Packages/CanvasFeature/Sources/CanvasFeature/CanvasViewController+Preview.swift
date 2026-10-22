import Geometry
import Model
import Rendering

/// The preview of this canvas for its card in the parent, at a leave event (m6-plan.md task 4.8,
/// D-97, D-111).
extension CanvasViewController {
    /// The card of this canvas in its parent, or `nil` if the app does not know it, for example
    /// after a launch into a child.
    public var parentCard: Card? { parentLink.card }

    /// Renders the preview of this canvas at the open camera, cut to the aspect of its card. The
    /// render runs in chunks on the frames of this screen, so the screen must stay until
    /// `completion` runs. `completion` runs off the main actor with the image, or `nil`.
    ///
    /// - Precondition: `cardAspect` is positive and finite.
    public func renderPreview(
        cardAspect: Double,
        completion: @escaping @Sendable (PreviewImage?) -> Void
    ) {
        precondition(cardAspect > 0 && cardAspect.isFinite, "Card aspect \(cardAspect)")
        renderer.renderPreview(
            camera: content.openCamera,
            cardAspect: cardAspect,
            completion: completion
        )
    }

    /// Shows a new preview of the child canvas of `card` without a read of its file.
    public func showPreview(_ image: PreviewImage, of card: CardID) {
        precondition(max(image.width, image.height) <= PreviewImage.maxSide, "Preview size")
        guard content.cards[card] != nil else { return }
        renderer.showPreview(image, of: card)
    }
}
