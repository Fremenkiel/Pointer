import CoreGraphics

/// Writes a PDF outside Export. Rule arch_04_pdf bans both calls (D-139).
func writePDF(into consumer: CGDataConsumer) {
    var box = CGRect(x: 0, y: 0, width: 10, height: 10)
    guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
    context.beginPDFPage(nil)
}
