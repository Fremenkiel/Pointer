import Foundation
import os

/// A picked snapshot file after its copy into `tmp/` and its checks (D-156, D-162). Only
/// `SnapshotImport` makes it, so a restore takes only a checked file.
public struct CheckedSnapshot: Sendable, Equatable {
    /// The copy in `tmp/`, `<uuid>.sqlite.partial`. The launch deletes a copy that stays.
    public let file: URL
    /// The schema version of the file, from 1 to the current version.
    public let version: Int64
}

/// Copies a picked snapshot into `tmp/` and checks the copy before a restore (storage.md
/// section 7.5, D-156, D-162).
///
/// The actor runs on its own serial queue, so the copy and the checks never run on the main
/// actor or on the shared pool. The app passes the URL of the document picker only.
public actor SnapshotImport {
    /// The most rows of `sqlite_schema` that a check reads. Version 1 has 13 (FLOW-03).
    static let maxSchemaRows = 64

    private let temporaryFolder: URL
    private let migrations: [Migration]
    private let files = FileManager()
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    private let queue = DispatchSerialQueue(label: "dk.saarikivi.pointer.import")

    /// The executor of the import: its own serial queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Makes an import that copies into `temporaryFolder`, the `tmp/` of the app.
    ///
    /// - Precondition: `temporaryFolder` is a file URL.
    public init(temporaryFolder: URL) {
        self.init(temporaryFolder: temporaryFolder, migrations: Migration.library)
    }

    init(temporaryFolder: URL, migrations: [Migration]) {
        precondition(temporaryFolder.isFileURL, "The temporary folder must be a file URL")
        precondition(!migrations.isEmpty, "The expected schema needs a migration")
        self.temporaryFolder = temporaryFolder
        self.migrations = migrations
    }

    /// Copies the picked file into `tmp/` and checks the copy (D-156, D-162).
    ///
    /// The copy runs inside the security scope of `picked` and in a coordinated read, which
    /// downloads a file of a provider first. A copy that fails a check goes at once.
    ///
    /// - Precondition: `picked` is a file URL.
    /// - Returns: The checked copy and its schema version.
    /// - Throws: `PersistenceError.diskFull` or `.fileFailed` if the copy fails, and the error
    ///   of the first check that refuses the file.
    public func copyAndCheck(_ picked: URL) throws(PersistenceError) -> CheckedSnapshot {
        precondition(picked.isFileURL, "A picked snapshot is a file, got \(picked)")
        let copy = temporaryFolder.appending(
            path: UUID().uuidString + LibraryMaintenance.partialSuffix
        )
        do {
            try SnapshotCopy.copy(picked, to: copy)
            let version = try check(copy)
            assert(version >= 1 && version <= Schema.currentVersion, "Version \(version)")
            return CheckedSnapshot(file: copy, version: version)
        } catch {
            logger.error("A picked snapshot was refused: \(error)")
            discard(at: copy)
            throw error
        }
    }

    /// Deletes the copy of a checked snapshot after the restore. A failed delete is only
    /// logged, because the launch deletes the file later.
    public func discard(_ snapshot: CheckedSnapshot) {
        precondition(snapshot.file.isFileURL, "A checked snapshot is a file")
        discard(at: snapshot.file)
    }

    /// Runs the checks of D-162 on the file at `copy`, in order: the header, a full
    /// `integrity_check` on a hardened read-only connection, and the schema of its version.
    ///
    /// - Returns: The schema version of the file.
    /// - Throws: The error of the first check that refuses the file.
    func check(_ copy: URL) throws(PersistenceError) -> Int64 {
        let path = copy.path(percentEncoded: false)
        let header = try SnapshotHeader(try SnapshotCopy.header(of: copy), fileSize: size(of: copy))
        do throws(PersistenceError) {
            let connection = try SQLiteConnection(path: path, mode: .untrustedReadOnly)
            let result = try connection.text("PRAGMA integrity_check")
            guard result == "ok" else { throw .integrityFailed(reason: result) }
            let version = try connection.integer("PRAGMA user_version")
            guard version == header.userVersion else {
                throw .integrityFailed(reason: "user_version \(version)")
            }
            try compareSchema(of: connection, version: version)
        } catch .sqlite(let code, let message) {
            // A damaged page can stop a read before `integrity_check` gives its rows.
            throw .integrityFailed(reason: "SQLite \(code): \(message)")
        }
        return header.userVersion
    }

    /// Compares the schema rows of the file with the rows of the migrations up to `version`,
    /// run in a database in memory (D-162, D-163).
    ///
    /// - Throws: `PersistenceError.schemaMismatch` with the first row that differs.
    private func compareSchema(
        of connection: SQLiteConnection,
        version: Int64
    ) throws(PersistenceError) {
        precondition(version >= 1 && version <= Int64(migrations.count), "Version \(version)")
        let expected = try SQLiteConnection(path: SQLiteConnection.memoryPath, mode: .memory)
        let runner = MigrationRunner(migrations: Array(migrations.prefix(Int(version))))
        _ = try runner.run(on: expected, hasSnapshot: false)
        let wanted = try Self.schemaRows(of: expected)
        let found = try Self.schemaRows(of: connection)
        guard found == wanted else {
            let difference = found.difference(from: wanted).first.map { change in
                switch change {
                case .insert(_, let row, _): "extra \(row)"
                case .remove(_, let row, _): "missing \(row)"
                }
            }
            throw .schemaMismatch(reason: difference ?? "the order of the rows")
        }
    }

    /// Returns the type, the name, the table, and the SQL of each row of `sqlite_schema`.
    ///
    /// - Throws: `PersistenceError.schemaMismatch` for more than `maxSchemaRows` rows.
    private static func schemaRows(
        of connection: SQLiteConnection
    ) throws(PersistenceError) -> [String] {
        let statement = try connection.prepare(
            """
            SELECT type || ' ' || name || ' ON ' || tbl_name || ': ' || coalesce(sql, '')
            FROM sqlite_schema ORDER BY type, name
            """
        )
        var rows: [String] = []
        while try statement.step() {
            guard rows.count < maxSchemaRows else {
                throw .schemaMismatch(reason: "more than \(maxSchemaRows) schema rows")
            }
            rows.append(statement.string(at: 0) ?? "")
        }
        assert(rows.count <= maxSchemaRows, "The read keeps the row bound")
        return rows
    }

    private func size(of copy: URL) throws(PersistenceError) -> Int {
        precondition(copy.isFileURL, "The copy is a file, got \(copy)")
        do {
            let attributes = try files.attributesOfItem(atPath: copy.path(percentEncoded: false))
            guard let size = attributes[.size] as? Int else { throw PersistenceError.notADatabase }
            return size
        } catch {
            throw .fileFailed(reason: "cannot read the size of the copy: \(error)")
        }
    }

    private func discard(at copy: URL) {
        precondition(copy.path.hasSuffix(LibraryMaintenance.partialSuffix), "Not a copy: \(copy)")
        precondition(
            copy.deletingLastPathComponent().path == temporaryFolder.path,
            "The import deletes only its own copies in tmp"
        )
        do {
            if files.fileExists(atPath: copy.path(percentEncoded: false)) {
                try files.removeItem(at: copy)
            }
        } catch {
            logger.error("The copy of a picked snapshot stays: \(error)")
        }
    }
}
