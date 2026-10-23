/// The errors of the PDF export (SAFE-04).
public enum ExportError: Error, Equatable, Sendable {
    /// The canvas has no stroke and no text box, so the export makes no PDF (D-142).
    case emptyCanvas
    /// Core Graphics did not make the PDF context.
    case pdfContextFailed
}
