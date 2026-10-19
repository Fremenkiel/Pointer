/// The errors of a canvas command (data-model.md section 9).
public enum CommandError: Error, Equatable, Sendable {
    /// The command adds more strokes than the canvas can hold (`Limits.maxStrokesPerCanvas`).
    case strokeLimitReached
    /// The command needs a live stroke that the content does not hold.
    case strokeNotLive(StrokeID)
    /// The command adds a stroke that the content already holds as a live stroke.
    case strokeAlreadyLive(StrokeID)
}
