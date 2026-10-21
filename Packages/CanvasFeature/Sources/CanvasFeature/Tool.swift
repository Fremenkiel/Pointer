/// A tool of the canvas (TOOL-01).
public enum Tool: Sendable, CaseIterable {
    /// Draws white ink.
    case pen
    /// Removes ink where the pencil touches it.
    case eraser
    /// Makes a text box where the pencil taps (TOOL-05, D-87).
    case text
}
