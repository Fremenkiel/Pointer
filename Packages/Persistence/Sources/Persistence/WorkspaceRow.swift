import Geometry
import Model

/// The SQL and the codec of the `workspace` table (storage.md section 3.3).
enum WorkspaceRow {
    /// The number of parameters of the write statement.
    static let parameterCount: Int32 = 6
    /// The number of columns of the read statement.
    static let columnCount: Int32 = 6

    /// Writes a workspace. A row with the same ID takes the new values.
    static let upsert: StaticString = """
        INSERT INTO workspace (id, title, sort_key, created, modified, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET title = excluded.title, sort_key = excluded.sort_key,
            modified = excluded.modified, is_deleted = excluded.is_deleted
        """

    /// Reads the live workspaces in the order of the selector.
    static let selectLive: StaticString = """
        SELECT id, title, sort_key, created, modified, is_deleted FROM workspace
        WHERE is_deleted = 0 ORDER BY sort_key, id
        """

    /// Binds `workspace` to the parameters of `upsert`.
    ///
    /// - Throws: `PersistenceError.sqlite` if a bind fails.
    static func bind(
        _ workspace: Workspace,
        to statement: SQLiteStatement
    ) throws(PersistenceError) {
        precondition(statement.parameterCount == parameterCount, "Not a workspace write")
        var binder = try RowBinder(statement)
        try binder.bind(workspace.id)
        try binder.bind(workspace.title)
        try binder.bind(workspace.sortKey.rawValue)
        try binder.bind(workspace.meta)
        assert(binder.count == statement.parameterCount, "Workspace binds all parameters")
    }

    /// Reads the current row of `selectLive`.
    ///
    /// - Throws: `PersistenceError.corruptRow` if a column does not give a valid workspace.
    static func read(from statement: SQLiteStatement) throws(PersistenceError) -> Workspace {
        precondition(statement.columnCount == columnCount, "Not a workspace read")
        var reader = RowReader(statement, table: "workspace")
        let id: WorkspaceID = try reader.identifier()
        let title = try reader.string()
        let sortKey = try reader.sortKey()
        let meta = try reader.meta()
        let workspace = try reader.make { () throws(ModelError) in
            try Workspace(id: id, meta: meta, title: title, sortKey: sortKey)
        }
        assert(!workspace.meta.isDeleted, "The live read gave tombstone \(workspace.id)")
        return workspace
    }
}
