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
    /// rows load (storage.md section 9). The rows that wait for a save are saved first, so the
    /// load holds them.
    ///
    /// - Throws: `ModelError.storageFailed` if the save of the waiting rows or a read fails.
    public func content(of canvasID: CanvasID) throws(ModelError) -> CanvasContent {
        let statements = try openStatements()
        // Rows inside the save throttle are newer than the file, so they go first (F-01).
        if !pending.isEmpty {
            try storage { () throws(PersistenceError) in try save() }
        }
        assert(pending.isEmpty, "A load reads the file after all pending rows")
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

    /// Returns the longest valid start of a stored navigation path, from one read of its cards
    /// (D-112). A valid card is live, and its parent is the canvas above it. The rows that wait
    /// for a save are saved first, so the read holds them.
    ///
    /// - Returns: The valid start, at most the first `Limits.maxDepth` cards of `cards`.
    /// - Throws: `ModelError.storageFailed` if the save of the waiting rows or the read fails.
    public func validPath(
        _ cards: [CardID],
        in workspace: WorkspaceID
    ) throws(ModelError) -> NavigationPath {
        let statements = try openStatements()
        if !pending.isEmpty {
            try storage { () throws(PersistenceError) in try save() }
        }
        // A damaged device file can hold a longer path. The check bounds it (FLOW-03).
        let path = Array(cards.prefix(Limits.maxDepth))
        var parents: [CardID: CanvasID] = [:]
        try storage { () throws(PersistenceError) in
            parents = try readParents(of: path, with: statements.selectPathCards)
        }
        var valid: [CardID] = []
        var above = CanvasID(workspace)
        for card in path {
            guard parents[card] == above else { break }
            valid.append(card)
            above = CanvasID(card)
        }
        assert(valid.count <= Limits.maxDepth, "A valid path holds at most the depth limit")
        do {
            return try NavigationPath(workspace: workspace, cards: valid)
        } catch {
            preconditionFailure("A path of \(valid.count) cards is within the limit")
        }
    }

    /// Reads the parent canvas of each live card of `path` in one query.
    ///
    /// - Precondition: `path` holds at most `Limits.maxDepth` cards.
    /// - Throws: `PersistenceError` if a bind, a step, or a column read fails.
    private func readParents(
        of path: [CardID],
        with statement: SQLiteStatement
    ) throws(PersistenceError) -> [CardID: CanvasID] {
        precondition(path.count <= Limits.maxDepth, "A path of \(path.count) cards is too long")
        var binder = try RowBinder(statement)
        for card in path {
            try binder.bind(card)
        }
        for _ in path.count..<Limits.maxDepth {
            try binder.bind(nil as String?)
        }
        var parents: [CardID: CanvasID] = [:]
        var rows = 0
        while rows < Limits.maxDepth, try statement.step() {
            rows += 1
            var reader = RowReader(statement, table: "card")
            let id: CardID = try reader.identifier()
            parents[id] = try reader.identifier()
        }
        try statement.reset()
        assert(parents.count <= path.count, "The read gave \(parents.count) cards")
        return parents
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
