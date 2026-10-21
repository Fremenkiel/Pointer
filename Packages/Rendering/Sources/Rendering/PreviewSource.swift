import Foundation
import Model

/// The stored previews of the child canvases: the PNG bytes of `Caches/Pointer/previews/`
/// (D-97, D-107). The app gives the renderer a source that reads them through `PreviewStore`, so
/// `Rendering` touches no file (ARCH-04).
public protocol PreviewSource: Sendable {
    /// Returns the PNG bytes of the preview of `canvas`. If no valid file exists, the source can
    /// render the preview of the canvas for a card of `cardAspect`, write it, and return it
    /// (m6-plan.md task 3.3, item 6). It returns `nil` if it has no preview.
    func preview(of canvas: CanvasID, cardAspect: Double) async -> Data?
}
