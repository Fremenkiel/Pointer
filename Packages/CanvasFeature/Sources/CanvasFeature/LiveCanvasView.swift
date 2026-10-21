import PencilKit
import UIKit

/// The live `PKCanvasView` of the pen (architecture.md 4.1). It never becomes the first
/// responder, so a finger tap on it does not take the keyboard from the edit view of a text box
/// (manual test 4 of docs/m5-plan.md section 5.6). Pointer uses no tool picker and no undo of
/// PencilKit, so the canvas needs no first responder.
@MainActor
final class LiveCanvasView: PKCanvasView {
    /// The live canvas never takes the first responder.
    override var canBecomeFirstResponder: Bool { false }
}
