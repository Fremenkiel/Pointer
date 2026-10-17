/// The errors of the Model package.
public enum ModelError: Error, Equatable, Sendable {
    /// The canvas holds `Limits.maxStrokesPerCanvas` strokes.
    case strokeLimitReached
    /// A pen path has no control points.
    case emptyPath
    /// A pen path has a point, a time, or a width that is not a finite number.
    case invalidPath(reason: String)
}
