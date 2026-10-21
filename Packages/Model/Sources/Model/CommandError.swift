/// The errors of a canvas command (data-model.md section 9).
public enum CommandError: Error, Equatable, Sendable {
    /// The command adds more strokes than the canvas can hold (`Limits.maxStrokesPerCanvas`).
    case strokeLimitReached
    /// The command needs a live stroke that the content does not hold.
    case strokeNotLive(StrokeID)
    /// The command adds a stroke that the content already holds as a live stroke.
    case strokeAlreadyLive(StrokeID)
    /// The command needs the erase record of a stroke that the content does not hold.
    case eraseRecordMissing(StrokeID)
    /// The command needs a live text box that the content does not hold.
    case textBoxNotLive(TextBoxID)
    /// The command adds a text box that the content already holds as a live box.
    case textBoxAlreadyLive(TextBoxID)
    /// The command needs a live card that the content does not hold.
    case cardNotLive(CardID)
    /// The command adds a card that the content already holds as a live card.
    case cardAlreadyLive(CardID)
    /// The command adds a node to a canvas that holds `Limits.maxNodesPerCanvas` nodes.
    case nodeLimitReached
}
