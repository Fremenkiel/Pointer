/// The size of a PDF page and the scale from canvas points to page points (D-142).
struct PageLayout: Equatable, Sendable {
    /// The width of the media box in PDF points.
    let width: Double
    /// The height of the media box in PDF points.
    let height: Double
    /// The page points per canvas point: 1, or less for a page over `PDFExporter.maxPageSide`.
    let scale: Double
}
