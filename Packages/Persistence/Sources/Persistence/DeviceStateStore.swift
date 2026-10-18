import Foundation
import Geometry
import Model
import os

/// The state of this iPad in `device.sqlite`: its device ID, the last workspace, the navigation
/// path, and one camera per canvas (storage.md section 10, D-53).
///
/// The actor runs on its own serial queue. A missing or damaged file gives a new file with a new
/// device ID. The damaged file stays as `device.sqlite.damaged`, and the app does not stop. The
/// camera positions are lost then, but no work is lost (STO-06).
public actor DeviceStateStore {
    /// The file and the source of a new device ID.
    public struct Configuration: Sendable {
        /// The path of `device.sqlite`.
        public let databasePath: String
        /// Makes the ID of this iPad for a new file.
        public let makeDeviceID: @Sendable () -> DeviceID

        /// Makes a configuration.
        public init(databasePath: String, makeDeviceID: @escaping @Sendable () -> DeviceID) {
            self.databasePath = databasePath
            self.makeDeviceID = makeDeviceID
        }
    }

    /// What the app needs at launch: the state and the camera of the last workspace.
    public struct Launch: Equatable, Sendable {
        /// The device state.
        public let state: DeviceState
        /// The camera of the root canvas of the last workspace, if one is stored.
        public let camera: Camera?
        /// True if the store made a new file, because the old one was missing or damaged.
        public let isNew: Bool
    }

    /// The most cameras that stay. A write drops the least recently used ones (D-53).
    static let maxCameras = 1_000
    static let deviceKey = "deviceID"
    static let lastWorkspaceKey = "lastWorkspace"
    static let navigationPathKey = "navigationPath"
    private static let keys: Set = [deviceKey, lastWorkspaceKey, navigationPathKey]

    private let configuration: Configuration
    private let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "Persistence")
    private let signposter = OSSignposter(
        subsystem: "dk.saarikivi.pointer",
        category: "Persistence"
    )
    private let queue = DispatchSerialQueue(label: "dk.saarikivi.pointer.device")
    private var connection: SQLiteConnection?
    private var statements: DeviceStatements?

    /// The executor of the store: its own serial queue.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    /// Makes a store. It opens nothing until `open()`.
    public init(configuration: Configuration) {
        precondition(!configuration.databasePath.isEmpty, "The device state needs a file path")
        self.configuration = configuration
    }

    /// Opens the file and reads the device rows and the camera of the last workspace only.
    ///
    /// A missing file gives a new one. A damaged file, a file with a newer schema, or a bad row
    /// gives a new file with a new device ID, and the old file stays as `device.sqlite.damaged`.
    ///
    /// - Precondition: The store is not open yet.
    /// - Throws: `PersistenceError` only if a new file cannot be made either.
    public func open() throws(PersistenceError) -> Launch {
        precondition(connection == nil, "The device state is open already")
        let interval = signposter.beginInterval("Device state launch")
        defer { signposter.endInterval("Device state launch", interval) }
        do {
            return try openFile()
        } catch {
            logger.fault("The device state is damaged and starts new: \(error)")
            close()
            moveDamagedFile()
            let launch = try openFile()
            assert(launch.isNew, "A new device state file was expected")
            return launch
        }
    }

    /// Returns the stored camera of `canvas`, or `nil` if none is stored or the row is bad.
    ///
    /// - Throws: `PersistenceError.sqlite` if the read fails.
    public func camera(for canvas: CanvasID) throws(PersistenceError) -> Camera? {
        let statements = try openStatements()
        let statement = statements.selectCamera
        var binder = try RowBinder(statement)
        try binder.bind(canvas)
        defer { resetAfterRead(statement) }
        guard try statement.step() else { return nil }
        let center = Point(x: statement.double(at: 0), y: statement.double(at: 1))
        let zoom = statement.double(at: 2)
        guard center.isFinite, Limits.zoomRange.contains(zoom) else {
            logger.error("Skipped a camera with a bad center or zoom")
            return nil
        }
        return Camera(center: center, zoom: zoom)
    }

    /// Writes the camera of `canvas` in one row and keeps the 1,000 most recently used cameras.
    ///
    /// - Precondition: The zoom is in `Limits.zoomRange`.
    /// - Throws: `PersistenceError.sqlite` if the write fails. The transaction then rolls back.
    public func save(_ camera: Camera, for canvas: CanvasID) throws(PersistenceError) {
        precondition(Limits.zoomRange.contains(camera.zoom), "Zoom \(camera.zoom) is out of range")
        let statements = try openStatements()
        try transaction(statements) { () throws(PersistenceError) in
            var binder = try RowBinder(statements.upsertCamera)
            try binder.bind(canvas)
            try binder.bind(camera.center.x)
            try binder.bind(camera.center.y)
            try binder.bind(camera.zoom)
            try LibraryStatements.run(statements.upsertCamera)
            var trim = try RowBinder(statements.trimCameras)
            try trim.bind(Int64(Self.maxCameras))
            try LibraryStatements.run(statements.trimCameras)
            // One write adds at most one row, so the trim removes at most one.
            assert(statements.trimCameras.changes <= 1, "The trim removed more than one camera")
        }
    }

    /// Writes the last workspace and the navigation path, for a change of the workspace or the
    /// move to the background.
    ///
    /// - Precondition: The path has at most `Limits.maxDepth` cards.
    /// - Throws: `PersistenceError.sqlite` if the write fails. The transaction then rolls back.
    public func save(
        lastWorkspace: WorkspaceID?,
        navigationPath: [CardID]
    ) throws(PersistenceError) {
        precondition(navigationPath.count <= Limits.maxDepth, "The path is deeper than the limit")
        let statements = try openStatements()
        try transaction(statements) { () throws(PersistenceError) in
            if let lastWorkspace {
                try write(Self.lastWorkspaceKey, ValueCodec.data(lastWorkspace), statements)
            } else {
                var binder = try RowBinder(statements.deleteValue)
                try binder.bind(Self.lastWorkspaceKey)
                try LibraryStatements.run(statements.deleteValue)
            }
            let path = navigationPath.reduce(into: Data()) { $0.append(ValueCodec.data($1)) }
            assert(path.count == navigationPath.count * ValueCodec.identifierByteCount, "Path size")
            try write(Self.navigationPathKey, path, statements)
        }
    }

    private func openFile() throws(PersistenceError) -> Launch {
        let opened = try SQLiteConnection(path: configuration.databasePath, mode: .readWrite)
        let runner = MigrationRunner(migrations: DeviceSchema.migrations)
        guard try runner.run(on: opened, hasSnapshot: false) == .current else {
            throw .corruptValue(reason: "the device file has a newer schema")
        }
        let prepared = try DeviceStatements(opened)
        connection = opened
        statements = prepared
        var isNew = false
        let deviceID: DeviceID
        if let stored = try value(Self.deviceKey, prepared) {
            deviceID = try ValueCodec.identifier(stored)
        } else {
            deviceID = configuration.makeDeviceID()
            try transaction(prepared) { () throws(PersistenceError) in
                try write(Self.deviceKey, ValueCodec.data(deviceID), prepared)
            }
            isNew = true
        }
        let state = try readState(deviceID: deviceID, prepared)
        var camera: Camera?
        if let workspace = state.lastWorkspace {
            camera = try self.camera(for: CanvasID(workspace))
        }
        assert(connection != nil && statements != nil, "The device state did not open")
        return Launch(state: state, camera: camera, isNew: isNew)
    }

    private func readState(
        deviceID: DeviceID,
        _ statements: DeviceStatements
    ) throws(PersistenceError) -> DeviceState {
        var workspace: WorkspaceID?
        if let data = try value(Self.lastWorkspaceKey, statements) {
            workspace = try ValueCodec.identifier(data)
        }
        let pathData = try value(Self.navigationPathKey, statements) ?? Data()
        let size = ValueCodec.identifierByteCount
        guard pathData.count % size == 0 else {
            throw .corruptValue(reason: "navigation path of \(pathData.count) bytes")
        }
        var path: [CardID] = []
        for start in stride(from: 0, to: pathData.count, by: size) {
            path.append(try ValueCodec.identifier(pathData.subdata(in: start..<start + size)))
        }
        assert(path.count * size == pathData.count, "The path lost bytes")
        do {
            return try DeviceState(
                deviceID: deviceID,
                lastWorkspace: workspace,
                navigationPath: path
            )
        } catch {
            throw .corruptValue(reason: "\(error)")
        }
    }

    private func value(
        _ key: String,
        _ statements: DeviceStatements
    ) throws(PersistenceError) -> Data? {
        precondition(Self.keys.contains(key), "Unknown device state key \(key)")
        let statement = statements.selectValue
        var binder = try RowBinder(statement)
        try binder.bind(key)
        defer { resetAfterRead(statement) }
        guard try statement.step() else { return nil }
        return statement.data(at: 0)
    }

    private func write(
        _ key: String,
        _ value: Data,
        _ statements: DeviceStatements
    ) throws(PersistenceError) {
        var binder = try RowBinder(statements.upsertValue)
        try binder.bind(key)
        try statements.upsertValue.bind(value, at: binder.count + 1)
        try LibraryStatements.run(statements.upsertValue)
    }

    private func transaction(
        _ statements: DeviceStatements,
        _ body: () throws(PersistenceError) -> Void
    ) throws(PersistenceError) {
        precondition(connection != nil, "A transaction needs an open device file")
        try LibraryStatements.run(statements.begin)
        do {
            try body()
            try LibraryStatements.run(statements.commit)
        } catch {
            rollBack(statements)
            throw error
        }
    }

    /// Rolls back. A failed rollback is only logged. The first error is the one to report.
    private func rollBack(_ statements: DeviceStatements) {
        do {
            try LibraryStatements.run(statements.rollback)
        } catch {
            logger.error("Rollback of the device state failed: \(error)")
        }
    }

    /// Resets a read, so the WAL file can be checkpointed. A failed reset is only logged.
    private func resetAfterRead(_ statement: SQLiteStatement) {
        do {
            try statement.reset()
        } catch {
            logger.error("Reset of a device state read failed: \(error)")
        }
    }

    private func openStatements() throws(PersistenceError) -> DeviceStatements {
        guard let statements else { throw .corruptValue(reason: "the device state is not open") }
        return statements
    }

    private func close() {
        statements = nil
        connection = nil
    }

    /// Keeps the damaged file as `device.sqlite.damaged` and removes its WAL files.
    private func moveDamagedFile() {
        precondition(connection == nil, "Close the damaged file before the move")
        let files = FileManager()
        let path = configuration.databasePath
        let damaged = path + ".damaged"
        do {
            if files.fileExists(atPath: damaged) { try files.removeItem(atPath: damaged) }
            if files.fileExists(atPath: path) { try files.moveItem(atPath: path, toPath: damaged) }
            for suffix in ["-wal", "-shm"] where files.fileExists(atPath: path + suffix) {
                try files.removeItem(atPath: path + suffix)
            }
            assert(!files.fileExists(atPath: path), "The damaged file is still in place")
        } catch {
            logger.fault("Cannot move the damaged device state: \(error)")
        }
    }
}
