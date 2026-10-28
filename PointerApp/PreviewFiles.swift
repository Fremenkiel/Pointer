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
/// preview offscreen, writes the file, and frees the content (the M6 plan task 3.3, item 6). The
/// loader of the renderer asks for one preview at a time, so one such load runs at a time.
struct PreviewFiles: PreviewSource {
    /// The store of the preview files.
    let store: PreviewStore
    /// The library, for the content of a child canvas without a preview.
    let repository: any LibraryRepository
    /// The offscreen renderer that the app shares among all canvases (D-157). It blocks on its
    /// own serial queue until the GPU completes, not on the shared pool.
    let maker: PreviewMaker
    /// Returns the size of the canvas screen at the time of a render, for the region of the open
    /// camera (D-98). A rotation changes it (review after M9, section 3.2, item 13).
    let viewSize: @Sendable () async -> Size
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
        let png: Data?
        do {
            png = try await maker.render(
                content,
                camera: content.openCamera,
                cardAspect: cardAspect,
                viewSize: await viewSize()
            ).pngData()
        } catch {
            logger.error(
                "The preview of a child canvas did not render: \(String(describing: error))"
            )
            return nil
        }
        guard let png else {
            logger.error("The preview of a child canvas did not encode")
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
