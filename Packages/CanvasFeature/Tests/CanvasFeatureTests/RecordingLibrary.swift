import Model

/// A library that records the rows and the save requests of the canvas (TEST-04).
actor RecordingLibrary: LibraryRepository {
    private(set) var rows: [LibraryChange] = []
    private(set) var saveRequests = 0

    func workspaces() throws(ModelError) -> [Workspace] { [] }
    func create(_ workspace: Workspace) throws(ModelError) {}
    func rename(_ id: WorkspaceID, to title: String, modified: HybridTimestamp) throws(ModelError) {
    }
    func delete(_ id: WorkspaceID, modified: HybridTimestamp) throws(ModelError) {}

    func content(of canvasID: CanvasID) throws(ModelError) -> CanvasContent {
        CanvasContent(canvasID: canvasID)
    }

    func validPath(
        _ cards: [CardID],
        in workspace: WorkspaceID
    ) throws(ModelError) -> NavigationPath {
        try NavigationPath(workspace: workspace, cards: Array(cards.prefix(Limits.maxDepth)))
    }

    func send(_ changes: [LibraryChange]) throws(ModelError) {
        rows += changes
    }

    func requestSave() {
        saveRequests += 1
    }

    func saveNow() throws(ModelError) {}
}
