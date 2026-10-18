import Model

extension SQLiteLibraryRepository {
    /// Writes a new workspace at once in its own transaction.
    ///
    /// - Precondition: `workspace` is not a tombstone.
    /// - Throws: `ModelError.workspaceLimitReached` at `Limits.maxWorkspaces` live workspaces,
    ///   `ModelError.libraryIsReadOnly`, or `ModelError.storageFailed`.
    public func create(_ workspace: Workspace) throws(ModelError) {
        precondition(!workspace.meta.isDeleted, "A new workspace cannot be a tombstone")
        let statements = try writableStatements()
        let count = try storage { () throws(PersistenceError) in
            let statement = statements.countWorkspaces
            let hasRow = try statement.step()
            let count = hasRow ? Int(clamping: statement.int64(at: 0)) : Limits.maxWorkspaces
            try statement.reset()
            return count
        }
        guard count < Limits.maxWorkspaces else { throw .workspaceLimitReached }
        try storage { () throws(PersistenceError) in
            try transaction(latest: workspace.meta.modified) { () throws(PersistenceError) in
                try WorkspaceRow.bind(workspace, to: statements.upsertWorkspace)
                try LibraryStatements.run(statements.upsertWorkspace)
            }
        }
    }

    /// Gives a live workspace a new title at once. The title is trimmed.
    ///
    /// - Throws: `ModelError.invalidTitle` or `ModelError.nullCharacter` for a bad title,
    ///   `ModelError.libraryIsReadOnly`, or `ModelError.storageFailed` if no live workspace has
    ///   the ID.
    public func rename(
        _ id: WorkspaceID,
        to title: String,
        modified: HybridTimestamp
    ) throws(ModelError) {
        precondition(
            modified.device == configuration.device,
            "A rename uses the clock of this device"
        )
        let trimmed = try Workspace.validatedTitle(title)
        let statements = try writableStatements()
        try storage { () throws(PersistenceError) in
            try transaction(latest: modified) { () throws(PersistenceError) in
                var binder = try RowBinder(statements.renameWorkspace)
                try binder.bind(trimmed)
                try binder.bind(modified)
                try binder.bind(id)
                try Self.runChangingOneRow(statements.renameWorkspace)
            }
        }
    }

    /// Marks a live workspace as deleted at once. The row stays as a tombstone for 30 days.
    ///
    /// - Throws: `ModelError.libraryIsReadOnly`, or `ModelError.storageFailed` if no live
    ///   workspace has the ID.
    public func delete(_ id: WorkspaceID, modified: HybridTimestamp) throws(ModelError) {
        precondition(
            modified.device == configuration.device,
            "A delete uses the clock of this device"
        )
        let statements = try writableStatements()
        try storage { () throws(PersistenceError) in
            try transaction(latest: modified) { () throws(PersistenceError) in
                var binder = try RowBinder(statements.deleteWorkspace)
                try binder.bind(modified)
                try binder.bind(id)
                try Self.runChangingOneRow(statements.deleteWorkspace)
            }
        }
    }

    /// Runs `body` and turns a storage error into `ModelError.storageFailed`.
    func storage<Value>(
        _ body: () throws(PersistenceError) -> Value
    ) throws(ModelError) -> Value {
        do {
            return try body()
        } catch {
            throw .storageFailed(reason: "\(error)")
        }
    }

    private static func runChangingOneRow(_ statement: SQLiteStatement) throws(PersistenceError) {
        _ = try statement.step()
        let changes = statement.changes
        try statement.reset()
        guard changes == 1 else { throw .corruptValue(reason: "no live workspace has the ID") }
    }
}
