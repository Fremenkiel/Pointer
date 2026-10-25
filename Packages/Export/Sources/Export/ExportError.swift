/// The errors of the PDF export (SAFE-04).
public enum ExportError: Error, Equatable, Sendable {
    /// The canvas has no stroke and no text box, so the export makes no PDF (D-142).
    case emptyCanvas
    /// Core Graphics did not make the PDF context.
    case pdfContextFailed
    /// The task of the export was cancelled, for example at the close of its canvas (review
    /// after M9, section 3.2, item 9).
    case cancelled
}
