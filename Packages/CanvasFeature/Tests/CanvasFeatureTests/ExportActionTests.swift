import Foundation
import Geometry
import Model
import PDFKit
import Rendering
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import CanvasFeature

/// The code behind the export button (EXP-01, EXP-04, D-87, D-142, D-143). A test cannot pick a
/// target in the share sheet, so the tests read the item provider that the share sheet gets.
@MainActor
@Suite("Export of the canvas")
struct ExportActionTests {
    /// The messages and the item providers of one screen.
    final class Record {
        var messages: [String] = []
        var providers: [NSItemProvider] = []
    }

    /// The content and the titles of one test screen.
    struct Setup {
        var strokes: [Stroke] = []
        var boxes: [TextBox] = []
        var cards: [Card] = []
        var parentCard: Card?
        var workspaceTitle: String? = "Trees"
    }

    static func makeController(_ setup: Setup, record: Record) throws -> CanvasViewController {
        var content = CanvasContent(canvasID: Fixtures.canvas)
        for stroke in setup.strokes { try content.add(stroke) }
        for box in setup.boxes { try content.add(box) }
        for card in setup.cards { try content.add(card) }
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(),
            clock: Fixtures.clock(),
            content: content
        )
        dependencies.camera = Camera(center: .zero, zoom: 1)
        dependencies.repository = RecordingLibrary()
        dependencies.onMessage = { [weak record] in record?.messages.append($0) }
        dependencies.parentCard = setup.parentCard
        let title = setup.workspaceTitle
        dependencies.workspaceTitle = { title }
        let controller = CanvasViewController(dependencies: dependencies)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        controller.view.layoutIfNeeded()
        controller.canvasExport.share = { [weak record] in record?.providers.append($0) }
        return controller
    }

    static func card(title: String?, id: UInt8 = 1) throws -> Card {
        try Card(
            id: CardID(rawValue: UUID(uuid: (7, id, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            meta: RecordMeta(
                created: HybridTimestamp(wallMillis: 1, counter: 0, device: Fixtures.device)
            ),
            canvasID: Fixtures.canvas,
            frame: Rect(origin: Point(x: 0, y: 0), size: Size(width: 100, height: 70)),
            title: title,
            sortKey: FractionalIndex(rawValue: "V")
        )
    }

    /// Exports and waits for the end of the export.
    static func export(_ controller: CanvasViewController) async {
        controller.exportCanvas()
        await controller.canvasExport.task?.value
    }

    /// Returns the text of the PDF of an item provider.
    static func pdfText(of provider: NSItemProvider) async throws -> String? {
        let data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .pdf) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        return PDFDocument(data: data)?.page(at: 0)?.string
    }

    @Test(
        "An empty canvas and a canvas with only cards show the message",
        arguments: [false, true]
    )
    func emptyCanvasShowsTheMessage(hasCard: Bool) async throws {
        let record = Record()
        let cards = hasCard ? [try Self.card(title: "Only")] : []
        let controller = try Self.makeController(Setup(cards: cards), record: record)
        controller.exportCanvas()
        #expect(controller.canvasExport.task == nil)
        #expect(!controller.historyControls.isExporting)
        #expect(record.messages == [CanvasStrings.exportEmpty])
        #expect(record.providers.isEmpty)
    }

    @Test("An export that ends after its canvas left the screen presents nothing (3.2.16)")
    func cancelAfterTheExport() async throws {
        let record = Record()
        let setup = Setup(strokes: [CanvasHistoryTests.line()])
        let controller = try Self.makeController(setup, record: record)
        controller.exportCanvas()
        // The task of the export starts and waits for the PDF.
        await Task.yield()
        // The PDF of one stroke is done long before the main thread runs again, so its result
        // waits for the main actor when the canvas leaves the screen.
        Self.holdMainThread(seconds: 0.2)
        controller.willMove(toParent: nil)
        await controller.canvasExport.task?.value
        #expect(record.providers.isEmpty)
        #expect(record.messages.isEmpty)
    }

    /// Blocks the main thread, so that no continuation runs on the main actor meanwhile.
    private static func holdMainThread(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @Test("A running text edit ends, and its text is in the PDF")
    func runningEditEnds() async throws {
        let record = Record()
        let controller = try Self.makeController(Setup(), record: record)
        controller.select(.text)
        controller.startNewTextBox(at: Point(x: 5, y: 5))
        controller.textEditing.view.text = "priority queue"
        await Self.export(controller)
        #expect(!controller.textEditing.isEditing)
        #expect(controller.content.textBoxes.values.first?.text == "priority queue")
        let provider = try #require(record.providers.first)
        let text = try #require(try await Self.pdfText(of: provider))
        #expect(text.contains("priority queue"))
        #expect(record.messages.isEmpty)
    }

    @Test("The item provider has the type PDF and the name of the workspace")
    func providerHasTypeAndName() async throws {
        let record = Record()
        let controller = try Self.makeController(
            Setup(strokes: [CanvasHistoryTests.line()]),
            record: record
        )
        await Self.export(controller)
        let provider = try #require(record.providers.first)
        #expect(provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier))
        #expect(provider.suggestedName == "Trees.pdf")
        #expect(record.providers.count == 1)
    }

    @Test("The PDF of a canvas in a card has the title of the card")
    func providerHasTheCardTitle() async throws {
        let record = Record()
        let setup = Setup(
            strokes: [CanvasHistoryTests.line()],
            parentCard: try Self.card(title: "AVL")
        )
        let controller = try Self.makeController(setup, record: record)
        await Self.export(controller)
        #expect(record.providers.first?.suggestedName == "AVL.pdf")
    }

    @Test("A second tap during an export starts no second export")
    func secondTapStartsNoExport() async throws {
        let record = Record()
        let controller = try Self.makeController(
            Setup(strokes: [CanvasHistoryTests.line()]),
            record: record
        )
        controller.exportCanvas()
        let first = try #require(controller.canvasExport.task)
        #expect(controller.historyControls.isExporting)
        controller.exportCanvas()
        #expect(controller.canvasExport.task == first)
        await first.value
        #expect(!controller.historyControls.isExporting)
        #expect(controller.canvasExport.task == nil)
        #expect(record.providers.count == 1)
    }

    @Test("The canvas screen goes away after an export")
    func screenGoesAwayAfterExport() async throws {
        let record = Record()
        let watched = try await Self.exportOnce(record: record)
        for _ in 0..<500 where watched.isAlive {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(record.providers.count == 1)
        #expect(!watched.isAlive)
    }

    /// Weak references to a canvas screen and its renderer.
    struct Watched {
        weak var canvas: CanvasViewController?
        weak var renderer: CanvasRenderer?

        var isAlive: Bool { canvas != nil || renderer != nil }
    }

    /// Exports one screen. The screen is a local of this function, so the caller holds no
    /// reference to it after it.
    private static func exportOnce(record: Record) async throws -> Watched {
        let controller = try makeController(
            Setup(strokes: [CanvasHistoryTests.line()]),
            record: record
        )
        await export(controller)
        return Watched(canvas: controller, renderer: controller.renderer)
    }
}
