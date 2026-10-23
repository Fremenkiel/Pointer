import Export
import Foundation
import Model
import UIKit
import UniformTypeIdentifiers

extension CanvasViewController {
    /// Exports the shown canvas as a PDF and opens the share sheet (EXP-01, EXP-04).
    ///
    /// A running text edit ends first, so the PDF holds its text (D-87). A canvas without
    /// strokes and text boxes shows a message and makes no PDF (D-142). The PDF is made off the
    /// main actor from a copy of the content, and the task holds the screen weakly.
    func exportCanvas() {
        guard canvasExport.task == nil else { return }
        endTextEdit()
        guard !content.strokes.isEmpty || !content.textBoxes.isEmpty else {
            onMessage(CanvasStrings.exportEmpty)
            return
        }
        let content = content
        let name = PDFFileName.name(
            cardTitle: parentLink.card?.title,
            workspaceTitle: canvasExport.workspaceTitle()
        )
        historyControls.isExporting = true
        canvasExport.task = Task { [weak self] in
            let result = await Task.detached {
                Result { () throws(ExportError) -> Data in try PDFExporter.pdfData(of: content) }
            }.value
            self?.finishExport(result, name: name)
        }
    }

    /// Returns the item provider that gives the PDF to the share sheet, without a file
    /// (ARCH-04, D-143).
    ///
    /// - Returns: A provider of the type PDF with the suggested name `name`.
    func exportItemProvider(for data: Data, name: String?) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(for: .pdf, visibility: .all) { load in
            load(data, nil)
            return nil
        }
        provider.suggestedName = name
        return provider
    }

    /// Ends an export: opens the share sheet with the PDF, or shows a message.
    private func finishExport(_ result: Result<Data, ExportError>, name: String?) {
        canvasExport.task = nil
        historyControls.isExporting = false
        switch result {
        case .success(let data):
            canvasExport.share(exportItemProvider(for: data, name: name))
        case .failure(.emptyCanvas):
            onMessage(CanvasStrings.exportEmpty)
        case .failure(let error):
            // The entry names the error only, never the content (SAFE-06).
            logger.error("The PDF export failed: \(String(describing: error))")
            onMessage(CanvasStrings.exportFailed)
        }
    }

    /// Opens the share sheet, with its popover at the export button (EXP-04).
    func presentShareSheet(_ provider: NSItemProvider) {
        let sheet = UIActivityViewController(
            activityItemsConfiguration: UIActivityItemsConfiguration(itemProviders: [provider])
        )
        if let anchor = canvasExport.anchor, let popover = sheet.popoverPresentationController {
            // The export button is the last square button at the right end of the row.
            let side = anchor.bounds.height
            popover.sourceView = anchor
            popover.sourceRect = CGRect(
                x: anchor.bounds.maxX - side,
                y: 0,
                width: side,
                height: side
            )
        }
        present(sheet, animated: true)
    }
}
