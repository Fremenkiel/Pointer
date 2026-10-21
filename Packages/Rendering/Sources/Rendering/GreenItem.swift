import Model

/// One item of the green channel of a committed texture: a text box or a card (D-82, D-96).
///
/// A build and a redraw list the cards and the text boxes of their area in one list, so one
/// cursor, one clear, and one glyph buffer serve both.
enum GreenItem: Hashable, Sendable {
    /// A text box.
    case textBox(TextBoxID)
    /// A card: its border, its title, and its preview.
    case card(CardID)
}
