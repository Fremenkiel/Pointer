extension SQLiteLibraryRepository {
    /// Closes the library, so that its files can go and `open(snapshot:)` can run again (D-148).
    ///
    /// The close ends the scheduled save and waits for the running checkpoint. Then it drops the
    /// statements, the checkpointer, and the connection. A send or a save after the close fails
    /// with `ModelError.storageFailed`, also one that comes during the wait.
    ///
    /// - Precondition: No row waits for a save. The caller saves first.
    public func close() async {
        precondition(pending.isEmpty, "The close drops \(pending.count) pending rows")
        scheduledSave?.cancel()
        scheduledSave = nil
        // Without statements, a send during the wait fails, so no row comes in.
        statements = nil
        await checkpointRequest?.value
        assert(checkpointRequest == nil, "The running checkpoint ended before the close")
        dropConnection()
    }

    /// Drops the statements, the checkpointer, and the connection, so the library is closed.
    /// A failed open calls it too, so that no write reaches the half-open file (review
    /// section 3.2, item 2).
    func dropConnection() {
        precondition(pending.isEmpty, "A closed library keeps no pending rows")
        assert(scheduledSave == nil, "A closed library has no scheduled save")
        // The statements hold the connection, so they go first.
        statements = nil
        checkpointRequest = nil
        checkpointer = nil
        connection = nil
        isReadOnly = false
        lastTimestamp = nil
        lastAttempt = nil
        failureCount = 0
        checkpointStartPages = 0
    }
}
