import Model

/// The prepared statements of the repository, compiled once at open and reused (storage.md 4).
final class LibraryStatements {
    let begin: SQLiteStatement
    let commit: SQLiteStatement
    let rollback: SQLiteStatement
    let insertStroke: SQLiteStatement
    let upsertErase: SQLiteStatement
    let upsertCard: SQLiteStatement
    let upsertTextBox: SQLiteStatement
    let upsertWorkspace: SQLiteStatement
    let renameWorkspace: SQLiteStatement
    let deleteWorkspace: SQLiteStatement
    let countWorkspaces: SQLiteStatement
    let selectWorkspaces: SQLiteStatement
    let selectStrokes: SQLiteStatement
    let selectCards: SQLiteStatement
    let selectPathCards: SQLiteStatement
    let selectTextBoxes: SQLiteStatement
    let writeLastTimestamp: SQLiteStatement

    /// Compiles all statements on `connection`.
    ///
    /// - Throws: `PersistenceError.sqlite` if a statement does not compile.
    init(_ connection: SQLiteConnection) throws(PersistenceError) {
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
