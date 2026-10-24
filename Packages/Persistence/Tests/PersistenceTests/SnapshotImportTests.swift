import Foundation
import Testing

@testable import Persistence

/// The copy and the checks of a picked snapshot (task 1.3 of docs/m9-plan.md, D-153, D-156,
/// D-162, D-163). `Fixtures/make-snapshot-fixtures.sh` makes the fixtures.
@Suite("Snapshot import")
struct SnapshotImportTests {
    @Test("The good snapshot passes, and its copy lies in tmp until the discard")
    func goodSnapshot() async throws {
        let folder = try TemporaryFolder()
        let importer = SnapshotImport(temporaryFolder: folder.url)
        let checked = try await importer.copyAndCheck(try Self.fixture("snapshot-good"))
        #expect(checked.version == 1)
        #expect(checked.file.deletingLastPathComponent().path == folder.url.path)
        #expect(checked.file.lastPathComponent.hasSuffix(LibraryMaintenance.partialSuffix))
        #expect(FileManager().fileExists(atPath: checked.file.path(percentEncoded: false)))
        await importer.discard(checked)
        #expect(try Self.names(in: folder).isEmpty)
    }

    @Test(
        "Each damaged or foreign fixture gives its error, and its copy goes",
        arguments: [
            ("snapshot-wrong-magic", PersistenceError.notADatabase),
            ("snapshot-page-8192", .wrongPageSize(bytes: 8192)),
            ("snapshot-wal", .walMode),
            ("snapshot-newer", .newerSchema(version: 2)),
            (
                "snapshot-damaged",
                .integrityFailed(reason: "row 1 missing from index sqlite_autoindex_stroke_1")
            ),
        ]
    )
    func refusedFixture(name: String, error: PersistenceError) async throws {
        let folder = try TemporaryFolder()
        let importer = SnapshotImport(temporaryFolder: folder.url)
        let picked = try Self.fixture(name)
        await #expect(throws: error) { _ = try await importer.copyAndCheck(picked) }
        #expect(try Self.names(in: folder).isEmpty)
    }

    @Test(
        "A fixture with another schema gives a schema mismatch",
        arguments: ["snapshot-missing-column", "snapshot-trigger"]
    )
    func schemaMismatch(name: String) async throws {
        let folder = try TemporaryFolder()
        let importer = SnapshotImport(temporaryFolder: folder.url)
        let picked = try Self.fixture(name)
        do {
            _ = try await importer.copyAndCheck(picked)
            Issue.record("\(name) passed the checks")
        } catch {
            guard case .schemaMismatch = error else {
                Issue.record("\(name) gave \(error)")
                return
            }
        }
        #expect(try Self.names(in: folder).isEmpty)
    }

    @Test("A view gives a schema mismatch")
    func view() async throws {
        let folder = try TemporaryFolder()
        let picked = try Self.edited("snapshot-good", in: folder) { connection in
            try connection.execute("CREATE VIEW everything AS SELECT * FROM stroke")
        }
        let importer = SnapshotImport(temporaryFolder: folder.url)
        await #expect(
            throws: PersistenceError.schemaMismatch(
                reason: "extra view everything ON everything: "
                    + "CREATE VIEW everything AS SELECT * FROM stroke"
            )
        ) { _ = try await importer.copyAndCheck(picked) }
    }

    @Test(
        "The header check refuses a short file, a cut file, and version 0",
        arguments: [
            (Edit.cut(toBytes: 50), PersistenceError.notADatabase),
            (.cut(toBytes: 0), .notADatabase),
            (.append(bytes: 100), .incompleteFile(byteCount: 69_732)),
            (.userVersion(0), .unknownVersion(0)),
            (.userVersion(-1), .unknownVersion(-1)),
        ]
    )
    func header(edit: Edit, error: PersistenceError) async throws {
        let folder = try TemporaryFolder()
        let source = try Data(contentsOf: try Self.fixture("snapshot-good"))
        let picked = folder.url.appending(path: "picked.sqlite")
        try edit.apply(to: source).write(to: picked)
        let importer = SnapshotImport(temporaryFolder: folder.url)
        await #expect(throws: error) { _ = try await importer.copyAndCheck(picked) }
        #expect(try Self.names(in: folder) == ["picked.sqlite"])
    }

    @Test("A file that does not exist gives a file error")
    func missingFile() async throws {
        let folder = try TemporaryFolder()
        let importer = SnapshotImport(temporaryFolder: folder.url)
        let picked = folder.url.appending(path: "missing.sqlite")
        await #expect(throws: PersistenceError.self) { _ = try await importer.copyAndCheck(picked) }
        #expect(try Self.names(in: folder).isEmpty)
    }

    @Test("An untrusted connection reads the file, writes nothing, and has the safe settings")
    func untrustedConnection() throws {
        let connection = try SQLiteConnection(
            path: try Self.fixture("snapshot-good").path(percentEncoded: false),
            mode: .untrustedReadOnly
        )
        #expect(try connection.integer("PRAGMA trusted_schema") == 0)
        #expect(try connection.integer("PRAGMA cell_size_check") == 1)
        #expect(try connection.integer("PRAGMA mmap_size") == 0)
        #expect(try connection.integer("SELECT count(*) FROM workspace") == 2)
        #expect(throws: PersistenceError.self) {
            try connection.execute("DELETE FROM workspace")
        }
    }

    /// A change of the bytes of a fixture.
    enum Edit: Sendable, CustomTestStringConvertible {
        case cut(toBytes: Int)
        case append(bytes: Int)
        case userVersion(Int32)

        var testDescription: String {
            switch self {
            case .cut(let bytes): "cut to \(bytes) bytes"
            case .append(let bytes): "\(bytes) bytes more"
            case .userVersion(let version): "user_version \(version)"
            }
        }

        func apply(to data: Data) -> Data {
            switch self {
            case .cut(let bytes): return data.prefix(bytes)
            case .append(let bytes): return data + Data(count: bytes)
            case .userVersion(let version):
                var edited = data
                let raw = UInt32(bitPattern: version)
                let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: raw >> $0) }
                edited.replaceSubrange(60..<64, with: bytes)
                return edited
            }
        }
    }

    /// Returns the URL of a fixture of the test bundle.
    static func fixture(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: "sqlite", subdirectory: "Fixtures")
        )
    }

    /// Copies a fixture into `folder`, changes it with `edit`, and returns the copy.
    static func edited(
        _ name: String,
        in folder: TemporaryFolder,
        _ edit: (SQLiteConnection) throws -> Void
    ) throws -> URL {
        let copy = folder.url.appending(path: "edited-\(name).sqlite")
        try FileManager().copyItem(at: try fixture(name), to: copy)
        let connection = try SQLiteConnection(
            path: copy.path(percentEncoded: false),
            mode: .readWrite
        )
        try edit(connection)
        // The write connection turns on WAL mode, and a snapshot is in rollback mode.
        _ = try connection.text("PRAGMA journal_mode = DELETE")
        return copy
    }

    private static func names(in folder: TemporaryFolder) throws -> [String] {
        try FileManager().contentsOfDirectory(atPath: folder.url.path(percentEncoded: false))
            .filter { !$0.hasPrefix("edited-") }
    }
}
