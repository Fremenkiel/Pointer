import Foundation
import Model
import os

/// The library on SQLite: the only code that writes the database (storage.md sections 4 and 5).
///
/// The actor runs on its own serial queue, so the blocking SQLite calls never hold a thread of
/// the shared pool and never run on the main actor (architecture.md section 11, PERF-02).
public actor SQLiteLibraryRepository: LibraryRepository {
    /// The files and the clocks of the repository.
    public struct Configuration: Sendable {
        /// The path of `library.sqlite`.
        public let databasePath: String
        /// The folder of the partial snapshot files (storage.md section 7.1).
        public let temporaryFolder: URL
        /// The device that creates a new library.
        public let device: DeviceID
        /// The wall clock for the creation time and the tombstone age.
        public let wallClock: any WallClock
        /// The monotonic clock of the save throttle.
        public let timer: any SaveTimer

        /// Makes a configuration.
        public init(
            databasePath: String,
            temporaryFolder: URL,
            device: DeviceID,
            wallClock: any WallClock,
            timer: any SaveTimer
        ) {
            self.databasePath = databasePath
            self.temporaryFolder = temporaryFolder
            self.device = device
            self.wallClock = wallClock
            self.timer = timer
        }
    }

    /// Writes the pre-migration snapshot of a library of the given old version (storage.md 6).
    public typealias PreMigrationSnapshot =
        @Sendable (_ oldVersion: Int64) async throws(PersistenceError) -> Void

    /// Receives the faults that the app shows.
    public typealias FaultHandler = @MainActor @Sendable (LibraryFault) -> Void

    /// The throttle interval of the saves (D-27).
    static let saveInterval = Duration.seconds(1)
    /// The failed saves in a row before the app shows a message (storage.md section 4).
    static let failuresBeforeFault = 3

    let configuration: Configuration
    /// The faults in the order of their reports. One task on the main actor gives them to the
    /// handler, so the app never sees a recovery before its failure.
    private let faultSink: AsyncStream<LibraryFault>.Continuation
    /// A test hook that runs between the last row and `COMMIT` (storage.md section 9).
    let beforeCommit: (@Sendable () throws(PersistenceError) -> Void)?
    /// The schema migrations. Tests add a version to test the pre-migration snapshot.
    let migrations: [Migration]
    let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    let signposter = OSSignposter(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    private let queue = DispatchSerialQueue(label: "dk.saarikivi.pointer.library")

    var connection: SQLiteConnection?
    var statements: LibraryStatements?
    var isReadOnly = false
    var pending = PendingRows()
    var lastTimestamp: HybridTimestamp?
    var lastAttempt: Duration?
    var failureCount = 0
    var scheduledSave: Task<Void, Never>?
    /// The checkpointer of the writable library, or `nil` (D-146).
    var checkpointer: WALCheckpointer?
    /// The running request to the checkpointer, or `nil`.
    var checkpointRequest: Task<Void, Never>?
    /// `false` in a test of the hard limit, which needs a library without a checkpointer.
    let usesCheckpointer: Bool
    /// A test hook that runs before each checkpoint of the checkpointer.
    let beforeCheckpoint: (@Sendable () -> Void)?
    /// The checkpoints that the write connection ran at the hard limit (D-147).
    var writeConnectionCheckpoints = 0
    /// The WAL pages when the running checkpoint of the checkpointer started (D-147).
    var checkpointStartPages = 0

    /// The executor of the repository: its own serial queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Makes a repository. It opens nothing until `open(snapshot:)`, so the initializer does no
    /// disk access on the caller's thread.
    public init(configuration: Configuration, onFault: @escaping FaultHandler) {
        self.init(configuration: configuration, onFault: onFault, beforeCommit: nil)
    }

    init(
        configuration: Configuration,
        onFault: @escaping FaultHandler,
        beforeCommit: (@Sendable () throws(PersistenceError) -> Void)?,
        migrations: [Migration] = Migration.library,
        usesCheckpointer: Bool = true,
        beforeCheckpoint: (@Sendable () -> Void)? = nil
    ) {
        precondition(!configuration.databasePath.isEmpty, "The library needs a file path")
        precondition(!migrations.isEmpty, "The library needs at least one migration")
        self.configuration = configuration
        let (faults, faultSink) = AsyncStream.makeStream(of: LibraryFault.self)
        self.faultSink = faultSink
        Task { @MainActor in
            for await fault in faults {
                do {
                    try Task.checkCancellation()
                } catch {
                    return
                }
                onFault(fault)
            }
        }
        self.beforeCommit = beforeCommit
        self.migrations = migrations
        self.usesCheckpointer = usesCheckpointer
        self.beforeCheckpoint = beforeCheckpoint
    }

    /// Opens the library, creates or migrates its schema, and cleans up (storage.md sections 5
    /// to 7).
    ///
    /// A newer schema opens read-only. A writable library gets its `library` rows (D-58), loses
    /// the tombstones older than 30 days (D-18), and gives free pages back. The partial snapshot
    /// files of a stopped snapshot are deleted first.
    ///
    /// - Precondition: The repository is not open: new, closed, or after a failed open.
    /// - Throws: `ModelError.storageFailed` if the file does not open or migrate.
    public func open(snapshot: PreMigrationSnapshot) async throws(ModelError) -> LibraryLaunch {
        precondition(connection == nil, "The library is open already")
        // A partial file of a stopped launch makes `VACUUM INTO` fail before the migration (F-08).
        LibraryMaintenance.removePartialSnapshots(in: configuration.temporaryFolder)
        do {
            try await openConnection(snapshot: snapshot)
            guard let connection else { preconditionFailure("The connection did not open") }
            if !isReadOnly {
                connection.trackWALPages()
                if usesCheckpointer {
                    checkpointer = try WALCheckpointer(
                        path: configuration.databasePath,
                        beforeCheckpoint: beforeCheckpoint
                    )
                }
                try writeCreationRows(on: connection)
                try LibraryMaintenance.removeTombstones(
                    on: connection,
                    now: configuration.wallClock
                )
            }
            lastTimestamp = try LibraryMaintenance.lastTimestamp(on: connection)
        } catch {
            dropConnection()
            throw .storageFailed(reason: "\(error)")
        }
        return LibraryLaunch(isReadOnly: isReadOnly, lastTimestamp: lastTimestamp)
    }

    private func openConnection(snapshot: PreMigrationSnapshot) async throws(PersistenceError) {
        precondition(connection == nil && statements == nil, "The library is open already")
        let path = configuration.databasePath
        var opened = try SQLiteConnection(path: path, mode: .readWrite)
        let runner = MigrationRunner(migrations: migrations)
        let oldVersion = try runner.snapshotVersion(of: opened)
        if let oldVersion {
            try await snapshot(oldVersion)
        }
        let outcome = try runner.run(on: opened, hasSnapshot: oldVersion != nil)
        if case .newer(let version) = outcome {
            logger.error("The library has schema \(version), newer than this app")
            opened = try SQLiteConnection(path: path, mode: .readOnly)
            isReadOnly = true
        }
        statements = try LibraryStatements(opened)
        connection = opened
        assert(isReadOnly == (outcome != .current), "Only a newer schema opens read-only")
    }

    private func writeCreationRows(on connection: SQLiteConnection) throws(PersistenceError) {
        precondition(!isReadOnly, "A read-only library gets no new rows")
        let created = HybridTimestamp(
            wallMillis: configuration.wallClock.nowMillis(),
            counter: 0,
            device: configuration.device
        )
        let statement = try connection.prepare(
            """
            INSERT INTO library (key, value) VALUES
                ('formatVersion', ?), ('created', ?), ('createdBy', ?), ('lastTimestamp', ?)
            ON CONFLICT (key) DO NOTHING
            """
        )
        var binder = try RowBinder(statement)
        try binder.bind(String(Schema.currentVersion))
        try binder.bind(ValueCodec.hex(created))
        try binder.bind(configuration.device.description)
        try binder.bind(ValueCodec.hex(created))
        assert(binder.count == statement.parameterCount, "The library rows bind all parameters")
        try LibraryStatements.run(statement)
    }

    /// Returns the statements, or throws if the library is read-only or not open.
    ///
    /// - Throws: `ModelError.libraryIsReadOnly` for a newer schema, and
    ///   `ModelError.storageFailed` before `open(snapshot:)`.
    func writableStatements() throws(ModelError) -> LibraryStatements {
        guard !isReadOnly else { throw .libraryIsReadOnly }
        return try openStatements()
    }

    /// Returns the statements of the open library.
    ///
    /// - Throws: `ModelError.storageFailed` before `open(snapshot:)`.
    func openStatements() throws(ModelError) -> LibraryStatements {
        guard let statements else { throw .storageFailed(reason: "the library is not open") }
        return statements
    }

    deinit {
        faultSink.finish()
    }

    /// Sends a fault to the main actor without waiting for it.
    func report(_ fault: LibraryFault) {
        faultSink.yield(fault)
    }
}
