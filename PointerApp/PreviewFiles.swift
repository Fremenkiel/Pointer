import Dispatch
import Foundation
import Geometry
import Model
import Persistence
import Rendering
import os

/// The card previews for the renderer: the files of `PreviewStore` (D-97, D-107).
///
/// A missing or damaged file starts one load of that child canvas alone. The source renders its
/// preview offscreen, writes the file, and frees the content (m6-plan.md task 3.3, item 6). The
/// loader of the renderer asks for one preview at a time, so one such load runs at a time.
struct PreviewFiles: PreviewSource {
    /// The queue of the offscreen render. The render blocks until the GPU completes, so it runs
    /// here and not on the shared pool of Swift concurrency.
    private static let renderQueue = DispatchQueue(
        label: "dk.saarikivi.pointer.preview-render",
        qos: .utility
    )

    /// The store of the preview files.
    let store: PreviewStore
    /// The library, for the content of a child canvas without a preview.
    let repository: any LibraryRepository
    /// The size of the canvas screen, for the region of the open camera (D-98).
    let viewSize: Size
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "App")

    /// Returns the PNG bytes of the preview of `canvas`. Without a valid file, it renders the
    /// preview of the canvas, writes the file, and returns its bytes.
    func preview(of canvas: CanvasID, cardAspect: Double) async -> Data? {
        if let data = await store.read(canvas) { return data }
        return await render(canvas, cardAspect: cardAspect)
    }

    private func render(_ canvas: CanvasID, cardAspect: Double) async -> Data? {
        let content: CanvasContent
        do {
            content = try await repository.content(of: canvas)
        } catch {
            logger.error("The child canvas of a preview did not load: \(String(describing: error))")
            return nil
        }
        let viewSize = viewSize
        let png = await withCheckedContinuation { continuation in
            Self.renderQueue.async {
                do {
                    let image = try PreviewMaker.render(
                        content,
                        camera: content.openCamera,
                        cardAspect: cardAspect,
                        viewSize: viewSize
                    )
                    continuation.resume(returning: image.pngData())
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
        guard let png else {
            logger.error("The preview of a child canvas did not render")
            return nil
        }
        do {
            try await store.write(png, for: canvas)
        } catch {
            logger.error("The preview file did not write: \(String(describing: error))")
        }
        return png
    }
}
