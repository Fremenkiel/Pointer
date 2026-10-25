/// The tool of the canvas and the rules of a tool change (architecture.md 4.4, D-70).
///
/// A tool change takes effect at the next pencil down. A stroke or an erase that runs ends with
/// the old tool. The drawing gesture of PencilKit is on only while the pen is active and the
/// library can save. The eraser also stops while the library cannot save.
struct ToolState: Equatable {
    /// The tool that the user picked last. The current-tool button shows it.
    private(set) var selected = Tool.pen
    /// The tool of the running pencil touch, or of the next one while the pencil is up.
    private(set) var active = Tool.pen
    /// `true` while the pencil touches the screen.
    private(set) var isPencilDown = false
    /// `false` while the library cannot save (storage.md section 4).
    var isEditingEnabled = true

    /// Picks a tool. It becomes active at once while the pencil is up, else at the next pencil
    /// down.
    mutating func select(_ tool: Tool) {
        selected = tool
        if !isPencilDown { active = tool }
        assert(isPencilDown || active == selected, "An idle pencil uses the selected tool")
    }

    /// Starts a pencil touch with the selected tool.
    ///
    /// - Returns: The tool of the touch.
    mutating func pencilDown() -> Tool {
        isPencilDown = true
        active = selected
        return active
    }

    /// Ends a pencil touch. A tool picked during the touch becomes active.
    mutating func pencilUp() {
        isPencilDown = false
        active = selected
    }

    /// `true` if the drawing gesture of PencilKit must be on.
    var isDrawingEnabled: Bool { isEditingEnabled && active == .pen }

    /// `true` if the pencil erases.
    var isErasingEnabled: Bool { isEditingEnabled && active == .eraser }

}
