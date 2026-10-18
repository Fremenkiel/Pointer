/// One changed row of a canvas that the canvas sends to the repository (storage.md section 4).
public enum LibraryChange: Sendable {
    /// A new stroke. Strokes never change after they are created.
    case stroke(Stroke)
    /// A new or changed erase record.
    case erase(EraseRecord)
    /// A new or changed card.
    case card(Card)
    /// A new or changed text box.
    case textBox(TextBox)
}
