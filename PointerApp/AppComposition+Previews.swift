import CanvasFeature
import Model
import Rendering

/// The write of the preview of a child canvas at each leave event of D-111: the up button, the
/// pinch-out exit, the workspace switch, and the move to the background (m6-plan.md task 4.8).
extension AppComposition {
    /// Stops the check for an idle moment and writes the preview of a child canvas on the
    /// screen. The move to the background starts here, because iOS refuses work on the GPU in
    /// the background (D-111).
    func resignActive() {
        stopIdleTimer()
        Task { await writeShownPreview() }
    }

    /// Renders the preview of the child of a leave while the parent loads. The leave ends only
    /// after the render, so the child stays on the screen until then.
    func renderPreview(of child: CanvasViewController, for card: Card, in leaving: CardOpening) {
        precondition(card.childCanvasID == child.canvasID, "The card of the child")
        leaving.isPreviewDone = false
        writePreview(of: child, card: card) { [weak self] image in
            leaving.preview = image
            leaving.isPreviewDone = true
            self?.finishLeave(into: card.id)
        }
    }

    /// Renders and writes the preview of the child canvas on the screen, and returns when the
    /// render ends. On the root canvas, it does nothing.
    func writeShownPreview() async {
        guard let path, path.level > 0, let canvas = container.canvas else { return }
        guard canvas.canvasID == path.currentCanvas else { return }
        guard let card = await card(of: canvas, in: path) else { return }
        await withCheckedContinuation { continuation in
            writePreview(of: canvas, card: card) { _ in continuation.resume() }
        }
    }

    /// The card of a child canvas in its parent. After a launch into the child, the app does not
    /// know it, so it loads the parent.
    private func card(of canvas: CanvasViewController, in path: NavigationPath) async -> Card? {
        if let card = canvas.parentCard { return card }
        guard let id = path.cards.last, let repository else { return nil }
        do {
            return try await repository.content(of: path.popping().currentCanvas).cards[id]
        } catch {
            logger.error("The parent of a preview did not load: \(String(describing: error))")
            return nil
        }
    }

    /// Renders the preview of `canvas` for `card`, gives it to `completion` on the main actor,
    /// and writes its file off the main actor (D-97).
    private func writePreview(
        of canvas: CanvasViewController,
        card: Card,
        completion: @escaping @MainActor (PreviewImage?) -> Void
    ) {
        let aspect = card.frame.size.width / card.frame.size.height
        precondition(aspect > 0 && aspect.isFinite, "A card has a positive size")
        let store = previewStore
        let canvasID = canvas.canvasID
        let logger = logger
        canvas.renderPreview(cardAspect: aspect) { image in
            Task { @MainActor in completion(image) }
            guard let png = image?.pngData(), let store else { return }
            Task {
                do {
                    try await store.write(png, for: canvasID)
                } catch {
                    logger.error("The preview file did not write: \(String(describing: error))")
                }
            }
        }
    }

    /// Removes the preview files of the canvases that the launch purge removed (D-18,
    /// m10-plan.md task 2.9). A file that stays costs disk space only, so a failure logs.
    func removePreviews(of canvases: [CanvasID]) async {
        guard let store = previewStore else { return }
        for canvas in canvases {
            do {
                try await store.remove(canvas)
            } catch {
                logger.error("The preview of a purged canvas stays: \(String(describing: error))")
            }
        }
    }
}
