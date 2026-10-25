import Foundation
import Geometry
import Model
import Persistence
import Rendering
import Synchronization
import Testing

@testable import Pointer

/// A library whose canvases all hold one ink line, for the previews.
private actor InkLibrary: LibraryRepository {
    let content: CanvasContent

    init(content: CanvasContent) {
        self.content = content
    }

    func workspaces() throws(ModelError) -> [Workspace] { [] }
    func create(_ workspace: Workspace) throws(ModelError) {}
    func rename(
        _ id: WorkspaceID,
        to title: String,
        modified: HybridTimestamp
    ) throws(ModelError) {}
    func delete(_ id: WorkspaceID, modified: HybridTimestamp) throws(ModelError) {}
    func content(of canvasID: CanvasID) throws(ModelError) -> CanvasContent { content }
    func validPath(
        _ cards: [CardID],
        in workspace: WorkspaceID
    ) throws(ModelError) -> NavigationPath {
        try NavigationPath(workspace: workspace)
    }
    func send(_ changes: [LibraryChange]) throws(ModelError) {}
    func requestSave() {}
    func saveNow() throws(ModelError) {}
}

/// The size of the canvas screen for each new preview (review after M9, section 3.2, item 13).
@MainActor
@Suite("Preview files")
struct PreviewFilesTests {
    @Test("A preview after a rotation uses the new size of the screen")
    func sizeAtRender() async throws {
        // swiftlint:disable:next arch_04_file_system
        let folder = FileManager().temporaryDirectory.appending(path: "Previews-\(UUID())")
        defer {
            do {
                // swiftlint:disable:next arch_04_file_system
                try FileManager().removeItem(at: folder)
            } catch {
                Issue.record("The test folder stays behind: \(error)")
            }
        }
        // An ink line from the center to the right edge of a landscape screen.
        let line = (0...60).map { Point(x: Double($0) * 10, y: 0) }
        let stroke = StrokeBuilder.stroke(line, seed: 1)
        var content = CanvasContent(canvasID: stroke.canvasID)
        try content.add(stroke)
        let size = Mutex(Size(width: 1_194, height: 834))
        let files = PreviewFiles(
            store: PreviewStore(folder: folder),
            repository: InkLibrary(content: content),
            maker: PreviewMaker(),
            viewSize: { size.withLock { $0 } }
        )
        let first = await files.preview(of: CanvasID(rawValue: UUID()), cardAspect: 1.5)
        size.withLock { $0 = Size(width: 834, height: 1_194) }
        let second = await files.preview(of: CanvasID(rawValue: UUID()), cardAspect: 1.5)
        let landscape = try #require(first)
        let portrait = try #require(second)
        #expect(landscape != portrait, "The second preview follows the rotated screen")
    }
}
