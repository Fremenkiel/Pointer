import os

/// Brings a database to the newest schema version (storage.md section 6).
struct MigrationRunner {
    /// The state of a database after the run.
    enum Outcome: Equatable {
        /// The database has the newest schema. The app can write.
        case current
        /// The database has a newer schema than the app knows. The app opens it read-only.
        case newer(version: Int64)
    }

    private let migrations: [Migration]
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")

    /// Makes a runner.
    ///
    /// - Precondition: `migrations` is not empty and has the versions 1, 2, 3, and so on.
    init(migrations: [Migration]) {
        precondition(!migrations.isEmpty, "A runner needs at least one migration")
        precondition(
            migrations.map(\.version) == Array(1...Int64(migrations.count)),
            "Migration versions must count up from 1"
        )
        self.migrations = migrations
    }

    /// The newest schema version of the runner.
    var targetVersion: Int64 { Int64(migrations.count) }

    /// Returns the old version if the database needs a pre-migration snapshot before `run`.
    ///
    /// An empty database of version 0 needs none, because it holds no data.
    ///
    /// - Throws: `PersistenceError.sqlite` if the version does not read.
    func snapshotVersion(of connection: SQLiteConnection) throws(PersistenceError) -> Int64? {
        let version = try connection.integer("PRAGMA user_version")
        return version > 0 && version < targetVersion ? version : nil
    }

    /// Runs the missing migrations on `connection` in one transaction.
    ///
    /// An empty database gets the newest schema. If a step fails, the transaction rolls back and
    /// the old schema stays.
    ///
    /// - Precondition: If `snapshotVersion(of:)` gives a version, the snapshot exists, and the
    ///   caller says so with `hasSnapshot` (storage.md section 6).
    /// - Returns: `.newer` without a change if the database is newer than the runner knows.
    /// - Throws: `PersistenceError.unknownSchema` for version 0 with tables, or
    ///   `PersistenceError.sqlite` for a failed step.
    func run(
        on connection: SQLiteConnection,
        hasSnapshot: Bool
    ) throws(PersistenceError) -> Outcome {
        let version = try connection.integer("PRAGMA user_version")
        guard version <= targetVersion else { return .newer(version: version) }
        guard version < targetVersion else { return .current }
        precondition(
            version == 0 || hasSnapshot,
            "Version \(version) migrates only after a snapshot"
        )
        if version == 0 {
            guard try connection.integer("SELECT count(*) FROM sqlite_schema") == 0 else {
                throw .unknownSchema
            }
        }
        try migrate(connection, from: version)
        return .current
    }

    private func migrate(
        _ connection: SQLiteConnection,
        from version: Int64
    ) throws(PersistenceError) {
        precondition(version < targetVersion, "Version \(version) needs no migration")
        try connection.execute("BEGIN IMMEDIATE")
        do {
            for migration in migrations where migration.version > version {
                try connection.execute(migration.statements)
                try connection.execute(migration.setVersion)
            }
            try connection.execute("COMMIT")
        } catch {
            rollBack(connection)
            throw error
        }
        assert(
            (try? connection.integer("PRAGMA user_version")) == targetVersion,
            "The migrations did not reach version \(targetVersion)"
        )
        logger.info("Migrated the library from version \(version) to \(targetVersion)")
    }

    /// Rolls back. SQLite rolls back by itself after some errors, so a failed rollback is only
    /// logged. The first error is the one to report.
    private func rollBack(_ connection: SQLiteConnection) {
        do {
            try connection.execute("ROLLBACK")
        } catch {
            logger.error("Rollback after a failed migration failed: \(error)")
        }
    }
}
