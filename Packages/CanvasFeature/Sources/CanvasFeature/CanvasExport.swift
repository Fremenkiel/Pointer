import UIKit

/// The state of the PDF export of a canvas screen (EXP-01, EXP-04).
@MainActor
final class CanvasExport {
    /// Gives the title of the workspace of the canvas, or `nil` if the app does not know it
    /// (D-143).
    let workspaceTitle: @MainActor () -> String?
    /// The running export, or `nil`. A second tap during an export starts none.
    var task: Task<Void, Never>?
    /// The view of the undo, redo, and export buttons. The share sheet points at it.
    weak var anchor: UIView?
    /// Opens the share sheet with the PDF. The canvas sets it, and a test can read the provider.
    var share: @MainActor (NSItemProvider) -> Void = { _ in }

    init(workspaceTitle: @escaping @MainActor () -> String?) {
        self.workspaceTitle = workspaceTitle
    }
}
