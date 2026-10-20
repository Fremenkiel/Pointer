import Model

extension SQLiteLibraryRepository {
    /// Returns the live workspaces in the order of the selector. A damaged row is skipped and
    /// reported (storage.md section 9).
    ///
    /// - Throws: `ModelError.storageFailed` if the read fails.
    public func workspaces() throws(ModelError) -> [Workspace] {
        let statements = try openStatements()
        var result: [Workspace] = []
        let query = RowQuery(
            statement: statements.selectWorkspaces,
            canvas: nil,
            table: "workspace",
            limit: Limits.maxWorkspaces,
            read: WorkspaceRow.read
        )
        try storage { () throws(PersistenceError) in
            try readRows(query) { (workspace: Workspace) throws(ModelError) in
                guard result.count < Limits.maxWorkspaces else { throw .workspaceLimitReached }
                result.append(workspace)
            }
        }
        assert(result.count <= Limits.maxWorkspaces, "Read \(result.count) workspaces")
        return result
    }

    /// Returns the live content of one canvas: cards, text boxes, and strokes without a live
    /// erase record (storage.md section 5). A damaged row is skipped and reported, and the other
    /// rows load (storage.md section 9).
    ///
    /// - Throws: `ModelError.storageFailed` if a read fails.
    public func content(of canvasID: CanvasID) throws(ModelError) -> CanvasContent {
        let statements = try openStatements()
        let interval = signposter.beginInterval("Load canvas")
        defer { signposter.endInterval("Load canvas", interval) }
        var content = CanvasContent(canvasID: canvasID)
        let cards = RowQuery(
            statement: statements.selectCards,
            canvas: canvasID,
            table: "card",
            limit: Limits.maxNodesPerCanvas,
            read: CardRow.read
        )
        let textBoxes = RowQuery(
            statement: statements.selectTextBoxes,
            canvas: canvasID,
            table: "text_box",
            limit: Limits.maxNodesPerCanvas,
            read: TextBoxRow.read
        )
        let strokes = RowQuery(
            statement: statements.selectStrokes,
            canvas: canvasID,
            table: "stroke",
            // An erase can pass the stroke limit by its parts (D-73).
            limit: Limits.maxStrokesAfterErase,
            read: StrokeRow.read
        )
        try storage { () throws(PersistenceError) in
            try readRows(cards) { (card: Card) throws(ModelError) in try content.add(card) }
            try readRows(textBoxes) { (box: TextBox) throws(ModelError) in try content.add(box) }
            try readRows(strokes) { (stroke: Stroke) throws(ModelError) in
                try content.add(stroke, limit: Limits.maxStrokesAfterErase)
            }
        }
        assert(content.canvasID == canvasID, "Loaded content of another canvas")
        assert(content.nodeCount <= Limits.maxNodesPerCanvas, "Loaded too many nodes")
        return content
    }

    /// Reads at most `query.limit + 1` rows and gives each valid row to `add`.
    ///
    /// A row that does not decode, or that `add` refuses at a limit, is skipped. The skipped
    /// rows go to the app as one fault per table.
    ///
    /// - Throws: `PersistenceError` if a step fails, for example on a damaged page.
    private func readRows<Row>(
        _ query: RowQuery<Row>,
        add: (Row) throws(ModelError) -> Void
    ) throws(PersistenceError) {
        precondition(query.limit > 0, "A query of \(query.table) needs a positive limit")
        let statement = query.statement
        var binder = try RowBinder(statement)
        if let canvas = query.canvas { try binder.bind(canvas) }
        var rows = 0
        var skipped = 0
        while rows <= query.limit, try statement.step() {
            rows += 1
            do {
                try add(try query.read(statement))
            } catch {
                skipped += 1
                logger.error("Skipped a row of \(query.table): \(error)")
            }
        }
        // The reset ends the read transaction, so the WAL file can be checkpointed.
        try statement.reset()
        assert(skipped <= rows, "Skipped \(skipped) of \(rows) rows")
        if skipped > 0 { report(.rowsSkipped(table: query.table, count: skipped)) }
    }
}

/// One read of live rows: the statement, its canvas parameter, and the codec of its rows.
struct RowQuery<Row> {
    let statement: SQLiteStatement
    let canvas: CanvasID?
    let table: String
    let limit: Int
    let read: (SQLiteStatement) throws(PersistenceError) -> Row
}
