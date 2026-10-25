import Model

/// The prepared statements of the repository, compiled once at open and reused (storage.md 4).
final class LibraryStatements {
    /// Holds `BEGIN IMMEDIATE`.
    let begin: SQLiteStatement
    /// Holds `COMMIT`.
    let commit: SQLiteStatement
    /// Holds `ROLLBACK`.
    let rollback: SQLiteStatement
    /// Holds `StrokeRow.insert`, which writes a stroke.
    let insertStroke: SQLiteStatement
    /// Holds `EraseRow.upsert`, which writes an erase record.
    let upsertErase: SQLiteStatement
    /// Holds `CardRow.upsert`, which writes a card.
    let upsertCard: SQLiteStatement
    /// Holds `TextBoxRow.upsert`, which writes a text box.
    let upsertTextBox: SQLiteStatement
    /// Holds `WorkspaceRow.upsert`, which writes a workspace.
    let upsertWorkspace: SQLiteStatement
    /// Sets the title of a live workspace.
    let renameWorkspace: SQLiteStatement
    /// Marks a live workspace as deleted.
    let deleteWorkspace: SQLiteStatement
    /// Counts the live workspaces.
    let countWorkspaces: SQLiteStatement
    /// Holds `WorkspaceRow.selectLive`, which reads the live workspaces.
    let selectWorkspaces: SQLiteStatement
    /// Holds `StrokeRow.selectLive`, which reads the live strokes of a canvas.
    let selectStrokes: SQLiteStatement
    /// Holds `CardRow.selectLive`, which reads the live cards of a canvas.
    let selectCards: SQLiteStatement
    /// Holds `CardRow.selectPath`, which reads the cards of a navigation path.
    let selectPathCards: SQLiteStatement
    /// Holds `TextBoxRow.selectLive`, which reads the live text boxes of a canvas.
    let selectTextBoxes: SQLiteStatement
    /// Writes the last timestamp of the clock to the `library` table.
    let writeLastTimestamp: SQLiteStatement

    /// Compiles all statements on `connection`.
    ///
    /// - Precondition: `connection` opened a library file, to read and write or to read only.
    /// - Throws: `PersistenceError.sqlite` if a statement does not compile.
    init(_ connection: SQLiteConnection) throws(PersistenceError) {
        precondition(
            connection.mode == .readWrite || connection.mode == .readOnly,
            "The statements of a library need a library file, got \(connection.mode)"
        )
        begin = try connection.prepare("BEGIN IMMEDIATE")
        commit = try connection.prepare("COMMIT")
        rollback = try connection.prepare("ROLLBACK")
        insertStroke = try connection.prepare(StrokeRow.insert)
        upsertErase = try connection.prepare(EraseRow.upsert)
        upsertCard = try connection.prepare(CardRow.upsert)
        upsertTextBox = try connection.prepare(TextBoxRow.upsert)
        upsertWorkspace = try connection.prepare(WorkspaceRow.upsert)
        renameWorkspace = try connection.prepare(
            "UPDATE workspace SET title = ?, modified = ? WHERE id = ? AND is_deleted = 0"
        )
        deleteWorkspace = try connection.prepare(
            "UPDATE workspace SET is_deleted = 1, modified = ? WHERE id = ? AND is_deleted = 0"
        )
        countWorkspaces = try connection.prepare(
            "SELECT count(*) FROM workspace WHERE is_deleted = 0"
        )
        selectWorkspaces = try connection.prepare(WorkspaceRow.selectLive)
        selectStrokes = try connection.prepare(StrokeRow.selectLive)
        selectCards = try connection.prepare(CardRow.selectLive)
        selectPathCards = try connection.prepare(CardRow.selectPath)
        selectTextBoxes = try connection.prepare(TextBoxRow.selectLive)
        writeLastTimestamp = try connection.prepare(
            """
            INSERT INTO library (key, value) VALUES ('lastTimestamp', ?)
            ON CONFLICT (key) DO UPDATE SET value = excluded.value
            """
        )
        checkShapes()
    }

    /// Asserts that the SQL and the codecs agree on the shape of each row.
    private func checkShapes() {
        assert(insertStroke.parameterCount == StrokeRow.parameterCount, "Stroke write shape")
        assert(selectStrokes.columnCount == StrokeRow.columnCount, "Stroke read shape")
        assert(upsertErase.parameterCount == EraseRow.parameterCount, "Erase write shape")
        assert(upsertCard.parameterCount == CardRow.parameterCount, "Card write shape")
        assert(selectCards.columnCount == CardRow.columnCount, "Card read shape")
        assert(selectPathCards.parameterCount == Int32(Limits.maxDepth), "Path read shape")
        assert(upsertTextBox.parameterCount == TextBoxRow.parameterCount, "Text box write shape")
        assert(selectTextBoxes.columnCount == TextBoxRow.columnCount, "Text box read shape")
        assert(
            upsertWorkspace.parameterCount == WorkspaceRow.parameterCount,
            "Workspace write shape"
        )
        assert(selectWorkspaces.columnCount == WorkspaceRow.columnCount, "Workspace read shape")
    }

    /// Runs a statement without result rows.
    ///
    /// - Throws: `PersistenceError.sqlite` if the step fails.
    static func run(_ statement: SQLiteStatement) throws(PersistenceError) {
        let hasRow = try statement.step()
        assert(!hasRow, "A write statement gave a row")
        try statement.reset()
    }
}
