import Model

extension SQLiteLibraryRepository {
    /// Returns the live workspaces in the order of the selector. A damaged row is skipped and
    /// reported (storage.md section 9).
    ///
    /// - Throws: `ModelError.storageFailed` if the read fails, and
    ///   `ModelError.workspaceLimitReached` if the library holds more than
    ///   `Limits.maxWorkspaces` live workspaces (review of 2026-10-28, 3.2.5).
    public func workspaces() throws(ModelError) -> [Workspace] {
        let statements = try openStatements()
        var result: [Workspace] = []
        let query = RowQuery(
            statement: statements.selectWorkspaces,
            count: statements.countWorkspaces,
            canvas: nil,
            table: "workspace",
            limit: Limits.maxWorkspaces,
            read: WorkspaceRow.read
        )
        let overLimit = try storage { () throws(PersistenceError) in
            try readRows(query) { (workspace: Workspace) throws(ModelError) in
                guard result.count < Limits.maxWorkspaces else { throw .workspaceLimitReached }
                result.append(workspace)
            }
        }
        guard overLimit == 0 else { throw .workspaceLimitReached }
        return result
    }

    /// Returns the live content of one canvas: cards, text boxes, and strokes without a live
    /// erase record (storage.md section 5). A damaged row is skipped and reported, and the other
    /// rows load (storage.md section 9). The rows past a limit of the canvas are skipped and
    /// reported with their count. The rows that wait for a save are saved first, so the load
    /// holds them.
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
        try storage { () throws(PersistenceError) in
            try reserveRows(of: canvasID, in: &content, statement: statements.countCanvasRows)
            let cards = statements.cards(of: canvasID)
            _ = try readRows(cards) { (card: Card) throws(ModelError) in try content.add(card) }
            let textBoxes = statements.textBoxes(of: canvasID)
            _ = try readRows(textBoxes) { (box: TextBox) throws(ModelError) in
                try content.add(box)
            }
            let strokes = statements.strokes(of: canvasID)
            _ = try readRows(strokes) { (stroke: Stroke) throws(ModelError) in
                try content.add(stroke, limit: Limits.maxStrokesAfterErase)
            }
        }
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
        // A row that does not decode throws in the middle of the rows. The reset ends the read
        // also then, because an open read pins the WAL file (D-146).
        defer { resetAfterRead(statement) }
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
        assert(parents.count <= path.count, "The read gave \(parents.count) cards")
        return parents
    }

    /// Reads at most `query.limit + 1` rows and gives each valid row to `add`.
    ///
    /// A row that does not decode is skipped. The first row that `add` refuses at a limit ends
    /// the read, because the rows after it do not fit either, and the count query of the table
    /// gives the number of rows that did not load (review of 2026-10-28, 3.2.5). The skipped
    /// rows go to the app as one fault per table.
    ///
    /// - Returns: The number of rows past the limit, or 0.
    /// - Throws: `PersistenceError` if a step fails, for example on a damaged page.
    private func readRows<Row>(
        _ query: RowQuery<Row>,
        add: (Row) throws(ModelError) -> Void
    ) throws(PersistenceError) -> Int {
        precondition(query.limit > 0, "A query of \(query.table) needs a positive limit")
        let statement = query.statement
        var binder = try RowBinder(statement)
        // The reset ends the read transaction, also after a failed step, so the WAL file can be
        // checkpointed.
        defer { resetAfterRead(statement) }
        if let canvas = query.canvas { try binder.bind(canvas) }
        var rows = 0
        var skipped = 0
        var overLimit = 0
        while rows <= query.limit, overLimit == 0, try statement.step() {
            rows += 1
            let row: Row
            do {
                row = try query.read(statement)
            } catch {
                skipped += 1
                logger.error("Skipped a row of \(query.table): \(error)")
                continue
            }
            do {
                try add(row)
            } catch {
                overLimit = max(try liveRows(query) - (rows - 1 - skipped), 1)
                logger.error("\(query.table): \(overLimit) rows past the limit: \(error)")
            }
        }
        if skipped + overLimit > 0 {
            report(.rowsSkipped(table: query.table, count: skipped + overLimit))
        }
        return overLimit
    }

    /// Counts the live rows of `query` with its count statement.
    ///
    /// - Throws: `PersistenceError` if the bind or the step fails.
    private func liveRows<Row>(_ query: RowQuery<Row>) throws(PersistenceError) -> Int {
        let statement = query.count
        var binder = try RowBinder(statement)
        defer { resetAfterRead(statement) }
        if let canvas = query.canvas { try binder.bind(canvas) }
        guard try statement.step() else {
            throw .corruptValue(reason: "no count of \(query.table)")
        }
        return Int(clamping: statement.int64(at: 0))
    }

    /// Reserves room in `content` for the rows of the canvas. The count costs 0.24 ms and saves
    /// about 1 ms of table growth for 20,000 strokes on the Mac (the M10 plan task 3.6).
    ///
    /// - Throws: `PersistenceError` if the bind or the step fails.
    private func reserveRows(
        of canvasID: CanvasID,
        in content: inout CanvasContent,
        statement: SQLiteStatement
    ) throws(PersistenceError) {
        var binder = try RowBinder(statement)
        defer { resetAfterRead(statement) }
        try binder.bind(canvasID)
        // The reserve only saves time, so the load goes on without it.
        guard try statement.step() else { return }
        content.reserveCapacity(
            strokes: max(Int(statement.int64(at: 0)), 0),
            cards: max(Int(statement.int64(at: 1)), 0),
            textBoxes: max(Int(statement.int64(at: 2)), 0)
        )
    }

    /// Resets a read, so the WAL file can be checkpointed. A failed reset is only logged.
    private func resetAfterRead(_ statement: SQLiteStatement) {
        do {
            try statement.reset()
        } catch {
            logger.error("Reset of a library read failed: \(error)")
        }
    }
}

/// One read of live rows: the statement, its canvas parameter, and the codec of its rows.
struct RowQuery<Row> {
    /// The prepared read.
    let statement: SQLiteStatement
    /// The prepared count of the live rows of the read, with the same canvas parameter.
    let count: SQLiteStatement
    /// The canvas that the read binds, or `nil` for a read without a canvas.
    let canvas: CanvasID?
    /// The table name for the log.
    let table: String
    /// The most rows that the read returns.
    let limit: Int
    /// Decodes one row.
    let read: (SQLiteStatement) throws(PersistenceError) -> Row
}

extension LibraryStatements {
    /// The read of the live cards of `canvas`.
    func cards(of canvas: CanvasID) -> RowQuery<Card> {
        RowQuery(
            statement: selectCards,
            count: countLiveCards,
            canvas: canvas,
            table: "card",
            limit: Limits.maxNodesPerCanvas,
            read: CardRow.read
        )
    }

    /// The read of the live text boxes of `canvas`.
    func textBoxes(of canvas: CanvasID) -> RowQuery<TextBox> {
        RowQuery(
            statement: selectTextBoxes,
            count: countLiveTextBoxes,
            canvas: canvas,
            table: "text_box",
            limit: Limits.maxNodesPerCanvas,
            read: TextBoxRow.read
        )
    }

    /// The read of the live strokes of `canvas`. An erase can pass the stroke limit by its
    /// parts (D-73), so the read takes `Limits.maxStrokesAfterErase`.
    func strokes(of canvas: CanvasID) -> RowQuery<Stroke> {
        RowQuery(
            statement: selectStrokes,
            count: countLiveStrokes,
            canvas: canvas,
            table: "stroke",
            limit: Limits.maxStrokesAfterErase,
            read: StrokeRow.read
        )
    }
}
