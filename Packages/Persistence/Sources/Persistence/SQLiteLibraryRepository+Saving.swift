import Model

extension SQLiteLibraryRepository {
    /// Adds changed rows to the pending set and starts the throttle (D-27).
    ///
    /// - Throws: `ModelError.libraryIsReadOnly` for a newer schema, and
    ///   `ModelError.storageFailed` before the library is open.
    public func send(_ changes: [LibraryChange]) throws(ModelError) {
        _ = try writableStatements()
        for change in changes {
            pending.add(change)
        }
        scheduleSave()
    }

    /// Asks for a save at pencil lift (storage.md section 4).
    public func requestSave() {
        scheduleSave()
    }

    /// Writes all pending rows at once, for the move to the background.
    ///
    /// - Throws: `ModelError.storageFailed` if the save fails. The rows stay pending, and the
    ///   throttle tries again at the end of the interval.
    public func saveNow() throws(ModelError) {
        scheduledSave?.cancel()
        scheduledSave = nil
        do {
            try storage { () throws(PersistenceError) in try save() }
        } catch {
            // The cancel above dropped the next try, so the rows need a new one (F-09).
            scheduleSave()
            assert(pending.isEmpty || scheduledSave != nil, "A failed save needs a retry")
            throw error
        }
        assert(pending.isEmpty, "A good save leaves no pending row")
    }

    /// The number of rows that wait for a save.
    public var pendingCount: Int { pending.count }

    /// Saves at once if the last attempt is older than the interval, else at its end. A write
    /// never waits for a pause in the input (storage.md section 4, review A-02).
    func scheduleSave() {
        guard !pending.isEmpty, scheduledSave == nil, !isReadOnly, statements != nil else { return }
        let now = configuration.timer.now()
        let due = lastAttempt.map { $0 + Self.saveInterval } ?? now
        if due > now { schedule(at: due) } else { attemptSave() }
        assert(pending.isEmpty || scheduledSave != nil, "Pending rows need a scheduled save")
    }

    /// Waits for the scheduled save if its time has come. Tests use it after they move the timer.
    func settle() async {
        guard let task = scheduledSave, let lastAttempt else { return }
        guard configuration.timer.now() >= lastAttempt + Self.saveInterval else { return }
        await task.value
    }

    private func schedule(at due: Duration) {
        precondition(scheduledSave == nil, "A save is scheduled already")
        let timer = configuration.timer
        // The task inherits the isolation of the actor. Only the sleep leaves it.
        scheduledSave = Task {
            do {
                try await timer.sleep(until: due)
            } catch {
                return
            }
            // A cancelled task must not clear the scheduled save of a newer task (F-10).
            guard !Task.isCancelled else { return }
            self.scheduledSaveFired()
        }
    }

    private func scheduledSaveFired() {
        scheduledSave = nil
        attemptSave()
    }

    /// Saves, and after a failure schedules the next try at the end of the interval.
    private func attemptSave() {
        do {
            try save()
        } catch {
            if let lastAttempt, !pending.isEmpty, scheduledSave == nil {
                schedule(at: lastAttempt + Self.saveInterval)
            }
        }
        assert(pending.isEmpty || scheduledSave != nil, "A failed save needs a retry")
    }

    /// Writes all pending rows and `lastTimestamp` in one transaction (storage.md section 4).
    ///
    /// After a failure, the rows stay pending. After three failures in a row, the app gets a
    /// fault. The first save that works after that gives `savesRecovered`.
    ///
    /// - Throws: `PersistenceError` of the failed transaction.
    func save() throws(PersistenceError) {
        guard !pending.isEmpty, let statements else { return }
        let previous = lastTimestamp
        defer { assert(lastTimestamp.map { $0 >= previous ?? $0 } ?? true, "The clock went back") }
        lastAttempt = configuration.timer.now()
        let interval = signposter.beginInterval("Save", "\(self.pending.count) rows")
        defer { signposter.endInterval("Save", interval) }
        do {
            try transaction(latest: pending.latest) { () throws(PersistenceError) in
                try write(pending, with: statements)
            }
        } catch {
            failureCount += 1
            logger.error("Save \(self.failureCount) in a row failed: \(error)")
            if failureCount >= Self.failuresBeforeFault {
                report(.savesFailing(count: failureCount, reason: "\(error)"))
            }
            throw error
        }
        pending = PendingRows()
        if failureCount >= Self.failuresBeforeFault { report(.savesRecovered) }
        failureCount = 0
        assert(pending.isEmpty, "A good save leaves no pending row")
    }

    /// Runs `body` and the write of `lastTimestamp` in one transaction (`BEGIN IMMEDIATE`).
    ///
    /// - Throws: The error of `body`, of the hook, or of `COMMIT`. The transaction then rolls
    ///   back, and `lastTimestamp` keeps its value.
    func transaction(
        latest: HybridTimestamp?,
        _ body: () throws(PersistenceError) -> Void
    ) throws(PersistenceError) {
        guard let statements else { preconditionFailure("A transaction needs an open library") }
        let newest = [lastTimestamp, latest].compactMap { $0 }.max()
        try LibraryStatements.run(statements.begin)
        do {
            try body()
            if let newest {
                var binder = try RowBinder(statements.writeLastTimestamp)
                try binder.bind(ValueCodec.hex(newest))
                try LibraryStatements.run(statements.writeLastTimestamp)
            }
            try beforeCommit?()
            try LibraryStatements.run(statements.commit)
        } catch {
            rollBack(statements)
            throw error
        }
        checkpointIfNeeded()
        lastTimestamp = newest
        assert(
            latest.map { latest in lastTimestamp.map { $0 >= latest } ?? false } ?? true,
            "The library clock value is older than a written row"
        )
    }

    /// Writes each pending row once. Strokes come before their erase records, because of the
    /// foreign key.
    private func write(
        _ rows: PendingRows,
        with statements: LibraryStatements
    ) throws(PersistenceError) {
        precondition(!rows.isEmpty, "A write needs rows")
        var written = 0
        defer { assert(written == rows.count, "Wrote \(written) of \(rows.count) rows") }
        for stroke in rows.strokes.values {
            try StrokeRow.bind(stroke, to: statements.insertStroke)
            try LibraryStatements.run(statements.insertStroke)
            written += 1
        }
        for record in rows.erases.values {
            try EraseRow.bind(record, to: statements.upsertErase)
            try LibraryStatements.run(statements.upsertErase)
            written += 1
        }
        for card in rows.cards.values {
            try CardRow.bind(card, to: statements.upsertCard)
            try LibraryStatements.run(statements.upsertCard)
            written += 1
        }
        for textBox in rows.textBoxes.values {
            try TextBoxRow.bind(textBox, to: statements.upsertTextBox)
            try LibraryStatements.run(statements.upsertTextBox)
            written += 1
        }
    }

    /// Rolls back. SQLite rolls back by itself after some errors, so a failed rollback is only
    /// logged. The first error is the one to report.
    private func rollBack(_ statements: LibraryStatements) {
        do {
            try LibraryStatements.run(statements.rollback)
        } catch {
            logger.error("Rollback failed: \(error)")
        }
    }
}
