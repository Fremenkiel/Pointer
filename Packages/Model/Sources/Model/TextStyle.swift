/// The style of the text of a text box (architecture.md sections 5.4 and 7).
///
/// The renderer, the edit view, and the export use these values, so that each one lays out a
/// text box with the same size.
public enum TextStyle {
    /// The font size in canvas points at zoom 1.0. The font is SF Mono (D-15).
    public static let fontSize = 17.0
    /// The largest width of a text box in canvas points. Longer lines wrap (D-83).
    public static let maxWidth = 640.0
}
