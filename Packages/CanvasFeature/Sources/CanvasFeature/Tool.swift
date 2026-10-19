/// A tool of the canvas (TOOL-01). The text tool comes in M5.
public enum Tool: Sendable, CaseIterable {
    /// Draws white ink.
    case pen
    /// Removes ink where the pencil touches it.
    case eraser
}
