import Foundation
import Model
import Persistence
import Rendering

/// The card previews for the renderer: the files of `PreviewStore` (D-97, D-107).
struct PreviewFiles: PreviewSource {
    /// The store of the preview files.
    let store: PreviewStore

    /// Returns the PNG bytes of the preview of `canvas`, or `nil` if no valid file exists.
    func preview(of canvas: CanvasID) async -> Data? {
        await store.read(canvas)
    }
}
