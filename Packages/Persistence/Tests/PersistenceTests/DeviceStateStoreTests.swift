import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

@Suite("Device state store")
struct DeviceStateStoreTests {
    static let firstDevice = DeviceID(
        rawValue: UUID(uuid: (9, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    static let secondDevice = DeviceID(
        rawValue: UUID(uuid: (9, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    @Test("A missing file gives a new state with a new device ID and no camera")
    func newFile() async throws {
        let folder = try TemporaryFolder()
        let launch = try await Self.store(folder).open()
        #expect(launch.isNew)
        #expect(
            launch.state
                == (try DeviceState(
                    deviceID: Self.firstDevice,
                    lastWorkspace: nil,
                    navigationPath: []
                ))
        )
        #expect(launch.camera == nil)
    }

    @Test("The device ID, the last workspace, the path, and the camera load again after a new open")
    func roundTrip() async throws {
        let folder = try TemporaryFolder()
        let first = Self.store(folder)
        _ = try await first.open()
        let path: [CardID] = [Values.id(11), Values.id(12), Values.id(13)]
        let camera = Camera(center: Point(x: -1_000_000.5, y: 2_000_000.25), zoom: 0.25)
        try await first.save(lastWorkspace: Values.workspaceID, navigationPath: path)
        try await first.save(camera, for: CanvasID(Values.id(13) as CardID))
        // The root canvas has a camera too, but the launch reads the deepest canvas (D-99).
        try await first.save(
            Camera(center: .zero, zoom: 1),
            for: CanvasID(Values.workspaceID)
        )

        let launch = try await Self.store(folder, device: Self.secondDevice).open()
        #expect(!launch.isNew)
        #expect(launch.state.deviceID == Self.firstDevice)
        #expect(launch.state.lastWorkspace == Values.workspaceID)
        #expect(launch.state.navigationPath == path)
        #expect(launch.camera == camera)
    }

    @Test("A closed store refuses a write and keeps its rows for the next open")
    func closeAndOpenAgain() async throws {
        let folder = try TemporaryFolder()
        let store = Self.store(folder)
        let first = try await store.open()
        try await store.save(lastWorkspace: Values.workspaceID, navigationPath: [])
        await store.close()
        await #expect(throws: PersistenceError.self) {
            try await store.save(lastWorkspace: nil, navigationPath: [])
        }
        let second = try await store.open()
        #expect(second.state.deviceID == first.state.deviceID)
        #expect(second.state.lastWorkspace == Values.workspaceID)
    }

    @Test("A cleared last workspace and an empty path load as cleared")
    func clearedState() async throws {
        let folder = try TemporaryFolder()
        let first = Self.store(folder)
        _ = try await first.open()
        try await first.save(lastWorkspace: Values.workspaceID, navigationPath: [Values.id(11)])
        try await first.save(lastWorkspace: nil, navigationPath: [])
        let launch = try await Self.store(folder).open()
        #expect(launch.state.lastWorkspace == nil)
        #expect(launch.state.navigationPath.isEmpty)
    }

    @Test(
        "The store keeps at most 1,000 cameras and drops the least recently used",
        arguments: [0, 1, 1_000, 1_001]
    )
    func cameraLimit(count: Int) async throws {
        let folder = try TemporaryFolder()
        let store = Self.store(folder)
        _ = try await store.open()
        let reader = try SQLiteConnection(path: folder.path("device.sqlite"), mode: .readOnly)
        try reader.execute("PRAGMA foreign_keys = ON")
        let canvases = (0..<count).map(Self.canvas)
        for (index, canvas) in canvases.enumerated() {
            try await store.save(
                Camera(center: Point(x: Double(index), y: 0), zoom: 1),
                for: canvas
            )
        }
        #expect(
            try reader.integer("SELECT count(*) FROM camera")
                == Int64(min(count, DeviceStateStore.maxCameras))
        )
        if count > DeviceStateStore.maxCameras {
            #expect(try await store.camera(for: canvases[0]) == nil)
            #expect(try await store.camera(for: canvases[1]) != nil)
        }
    }

    @Test("A camera write makes that camera the most recent, so a later trim keeps it")
    func recentUse() async throws {
        let folder = try TemporaryFolder()
        let store = Self.store(folder)
        _ = try await store.open()
        for index in 0..<DeviceStateStore.maxCameras {
            try await store.save(Camera(center: .zero, zoom: 1), for: Self.canvas(index))
        }
        try await store.save(Camera(center: Point(x: 5, y: 5), zoom: 2), for: Self.canvas(0))
        try await store.save(Camera(center: .zero, zoom: 1), for: Self.canvas(5_000))
        #expect(
            try await store.camera(for: Self.canvas(0))
                == Camera(center: Point(x: 5, y: 5), zoom: 2)
        )
        #expect(try await store.camera(for: Self.canvas(1)) == nil)
    }

    @Test(
        "A damaged file starts a new state and stays as device.sqlite.damaged",
        arguments: [
            Damage.notADatabase, .shortDeviceID, .newerSchema, .longPath, .badPath,
        ]
    )
    func damagedFile(damage: Damage) async throws {
        let folder = try TemporaryFolder()
        let first = Self.store(folder)
        _ = try await first.open()
        try await first.save(lastWorkspace: Values.workspaceID, navigationPath: [])
        try damage.apply(folder.path("device.sqlite"))

        let launch = try await Self.store(folder, device: Self.secondDevice).open()
        #expect(launch.isNew)
        #expect(launch.state.deviceID == Self.secondDevice)
        #expect(launch.state.lastWorkspace == nil)
        let names = try FileManager().contentsOfDirectory(atPath: folder.url.path)
        #expect(names.contains("device.sqlite.damaged"))
    }

    @Test("A camera with a zoom outside the range reads as no camera")
    func badCamera() async throws {
        let folder = try TemporaryFolder()
        let store = Self.store(folder)
        _ = try await store.open()
        try await store.save(Camera(center: .zero, zoom: 1), for: Values.canvas)
        let writer = try SQLiteConnection(path: folder.path("device.sqlite"), mode: .readWrite)
        try writer.execute("PRAGMA ignore_check_constraints = ON; UPDATE camera SET zoom = 100;")
        #expect(try await store.camera(for: Values.canvas) == nil)
    }

    enum Damage: Sendable {
        case notADatabase, shortDeviceID, newerSchema, longPath, badPath

        func apply(_ path: String) throws {
            switch self {
            case .notADatabase:
                for suffix in ["", "-wal", "-shm"] {
                    try Data(repeating: 0x41, count: 4096).write(to: URL(filePath: path + suffix))
                }
            case .shortDeviceID:
                try SQLiteConnection(path: path, mode: .readWrite)
                    .execute("UPDATE device SET value = zeroblob(15) WHERE key = 'deviceID'")
            case .newerSchema:
                try SQLiteConnection(path: path, mode: .readWrite).execute(
                    "PRAGMA user_version = 2"
                )
            case .longPath:
                try SQLiteConnection(path: path, mode: .readWrite).execute(
                    "UPDATE device SET value = zeroblob(16 * 33) WHERE key = 'navigationPath'"
                )
            case .badPath:
                try SQLiteConnection(path: path, mode: .readWrite).execute(
                    "UPDATE device SET value = zeroblob(17) WHERE key = 'navigationPath'"
                )
            }
        }
    }

    static func canvas(_ index: Int) -> CanvasID {
        CanvasID(
            rawValue: UUID(
                uuid: (
                    8, UInt8(index >> 8 & 0xFF), UInt8(index & 0xFF), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0
                )
            )
        )
    }

    static func store(
        _ folder: TemporaryFolder,
        device: DeviceID = firstDevice
    ) -> DeviceStateStore {
        DeviceStateStore(
            configuration: DeviceStateStore.Configuration(
                databasePath: folder.path("device.sqlite"),
                makeDeviceID: { device }
            )
        )
    }
}
