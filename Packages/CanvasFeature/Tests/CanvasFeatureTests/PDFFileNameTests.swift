import Testing

@testable import CanvasFeature

@Suite("File name of a shared PDF")
struct PDFFileNameTests {
    /// The titles of one case and the expected name (D-143).
    struct Case: Sendable {
        let card: String?
        let workspace: String?
        let expected: String?
    }

    static let cases = [
        Case(card: "AVL", workspace: "Trees", expected: "AVL.pdf"),
        Case(card: nil, workspace: "Trees", expected: "Trees.pdf"),
        Case(card: "  ", workspace: "Trees", expected: "Trees.pdf"),
        Case(card: nil, workspace: nil, expected: nil),
        Case(card: "a/b:c\td", workspace: "Trees", expected: "a-b-c-d.pdf"),
        Case(card: "Bäume 🌳", workspace: nil, expected: "Bäume 🌳.pdf"),
    ]

    @Test("The name is the card title, or else the workspace title", arguments: cases)
    func name(of testCase: Case) {
        let name = PDFFileName.name(cardTitle: testCase.card, workspaceTitle: testCase.workspace)
        #expect(name == testCase.expected)
    }

    @Test("A long title fits the name limit of the file system")
    func longTitleFits() throws {
        let title = String(repeating: "漢", count: 120)
        let name = try #require(PDFFileName.name(cardTitle: title, workspaceTitle: nil))
        #expect(name.utf8.count <= PDFFileName.maxBytes)
        #expect(name.hasSuffix(".pdf"))
        #expect(name.hasPrefix("漢漢"))
    }
}
