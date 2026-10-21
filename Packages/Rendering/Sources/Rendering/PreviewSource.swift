import Foundation
import Model

/// The stored previews of the child canvases: the PNG bytes of `Caches/Pointer/previews/`
/// (D-97, D-107). The app gives the renderer a source that reads them through `PreviewStore`, so
/// `Rendering` touches no file (ARCH-04).
public protocol PreviewSource: Sendable {
    /// Returns the PNG bytes of the preview of `canvas`, or `nil` if no valid file exists.
    func preview(of canvas: CanvasID) async -> Data?
}
