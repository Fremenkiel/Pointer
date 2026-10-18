import Foundation
import Model
import os

/// The cleanup of the library at launch (storage.md sections 5 and 7.1).
enum LibraryMaintenance {
    private static let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    /// The age of a tombstone before the launch removes it: 30 days (D-18).
    static let tombstoneLifetimeMillis: UInt64 = 30 * 24 * 60 * 60 * 1000
    /// The file name end of a snapshot that stopped before its rename (storage.md section 7.1).
    static let partialSuffix = ".sqlite.partial"

    /// Removes the tombstones older than 30 days and gives the free pages back.
    ///
    /// This covers deleted workspaces and cards with their subtrees, deleted text boxes, and
    /// erased strokes with their erase records (review A-07). The walk down the card tree stops
    /// at `Limits.maxDepth` (FLOW-01).
    ///
    /// - Throws: `PersistenceError.sqlite` if a step fails. The transaction then rolls back.
    static func removeTombstones(
        on connection: SQLiteConnection,
        now: any WallClock
    ) throws(PersistenceError) {
        assert(Limits.maxDepth == 32, "The tree walk in cutoffStatements uses depth 32")
        let nowMillis = now.nowMillis()
        let cutoffMillis =
            nowMillis > tombstoneLifetimeMillis ? nowMillis - tombstoneLifetimeMillis : 0
        let zeroDevice = DeviceID(rawValue: UUID(uuid: UUID_NULL))
        let cutoff = HybridTimestamp(wallMillis: cutoffMillis, counter: 0, device: zeroDevice)
        try connection.execute("BEGIN IMMEDIATE")
        do {
            try connection.execute(
                """
                CREATE TEMP TABLE doomed_canvas (id BLOB PRIMARY KEY);
                CREATE TEMP TABLE doomed_stroke (id BLOB PRIMARY KEY);
                """
            )
            for sql in cutoffStatements {
                let statement = try connection.prepare(sql)
                try statement.bind(ValueCodec.data(cutoff), at: 1)
                try LibraryStatements.run(statement)
            }
            try connection.execute(removeDoomed)
            try connection.execute("COMMIT")
            assert(
                (try? connection.integer("SELECT count(*) FROM sqlite_temp_schema")) == 0,
                "The cleanup left a temporary table"
            )
        } catch {
            rollBack(connection)
            throw error
        }
        try connection.execute("PRAGMA incremental_vacuum")
    }

    /// Rolls back. SQLite rolls back by itself after some errors, so a failed rollback is only
    /// logged. The first error is the one to report.
    private static func rollBack(_ connection: SQLiteConnection) {
        do {
            try connection.execute("ROLLBACK")
        } catch {
            logger.error("Rollback of the tombstone cleanup failed: \(error)")
        }
    }

    /// Returns the `lastTimestamp` row of the library, or `nil` if it has none.
    ///
    /// - Throws: `PersistenceError.corruptValue` if the row is not 56 lowercase hex digits.
    static func lastTimestamp(
        on connection: SQLiteConnection
    ) throws(PersistenceError) -> HybridTimestamp? {
        let statement = try connection.prepare(
            "SELECT value FROM library WHERE key = 'lastTimestamp'"
        )
        guard try statement.step() else { return nil }
        guard let hex = statement.string(at: 0) else {
            throw .corruptValue(reason: "lastTimestamp")
        }
        return try ValueCodec.timestamp(hex: hex)
    }

    /// Deletes each `*.sqlite.partial` file in `folder`. A failure is logged, not thrown.
    static func removePartialSnapshots(in folder: URL) {
        precondition(folder.isFileURL, "The temporary folder must be a file URL")
        let files = FileManager()
        let names: [String]
        do {
            names = try files.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        } catch {
            logger.error("Cannot list the temporary folder: \(error)")
            return
        }
        for name in names where name.hasSuffix(partialSuffix) {
            do {
                try files.removeItem(at: folder.appending(path: name))
            } catch {
                logger.error("Cannot delete a partial snapshot: \(error)")
            }
        }
    }

    /// The statements that take the cutoff clock value as parameter 1.
    private static let cutoffStatements: [StaticString] = [
        """
        WITH RECURSIVE doomed (id, depth) AS (
            SELECT id, 0 FROM workspace WHERE is_deleted = 1 AND modified < ?1
            UNION ALL SELECT id, 0 FROM card WHERE is_deleted = 1 AND modified < ?1
            -- 32 is Limits.maxDepth (CARD-09). SQL cannot read the Swift constant.
            UNION ALL SELECT card.id, doomed.depth + 1 FROM card
                JOIN doomed ON card.canvas_id = doomed.id WHERE doomed.depth < 32
        )
        INSERT OR IGNORE INTO doomed_canvas SELECT id FROM doomed
        """,
        """
        INSERT OR IGNORE INTO doomed_stroke
        SELECT stroke_id FROM stroke_erase WHERE is_deleted = 0 AND erased < ?1
        """,
        "DELETE FROM text_box WHERE is_deleted = 1 AND modified < ?1",
    ]

    /// Removes the rows of the doomed canvases and strokes. Erase records go before their
    /// strokes, because of the foreign key.
    private static let removeDoomed: StaticString = """
        INSERT OR IGNORE INTO doomed_stroke
            SELECT id FROM stroke WHERE canvas_id IN (SELECT id FROM doomed_canvas);
        DELETE FROM stroke_erase WHERE stroke_id IN (SELECT id FROM doomed_stroke);
        DELETE FROM stroke WHERE id IN (SELECT id FROM doomed_stroke);
        DELETE FROM text_box WHERE canvas_id IN (SELECT id FROM doomed_canvas);
        DELETE FROM card WHERE canvas_id IN (SELECT id FROM doomed_canvas)
            OR id IN (SELECT id FROM doomed_canvas);
        DELETE FROM workspace WHERE id IN (SELECT id FROM doomed_canvas);
        DROP TABLE doomed_canvas;
        DROP TABLE doomed_stroke;
        """
}
