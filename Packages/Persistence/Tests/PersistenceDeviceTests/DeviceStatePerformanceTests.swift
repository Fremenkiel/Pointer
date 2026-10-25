import Foundation
import Geometry
import Model
import Persistence
import XCTest

/// The launch read of the device state on the device (D-53): the device rows and the camera of
/// the last workspace, from a file with 1,000 cameras. The times are valid on a device only.
@MainActor
final class DeviceStatePerformanceTests: XCTestCase {
    /// The cameras in the file: the limit of D-53.
    private static let cameraCount = 1_000
    /// The opens of the measurement.
    private static let openCount = 20

    func testLaunchReadWithOneThousandCameras() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Read times are valid on a device only.")
        #else
            let files = FileManager()
            let folder = files.temporaryDirectory.appending(
                path: "DeviceState-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { Self.removeFolder(folder, files) }
            let configuration = DeviceStateStore.Configuration(
                databasePath: folder.appending(path: "device.sqlite").path(percentEncoded: false),
                makeDeviceID: { DeviceID(rawValue: UUID()) }
            )
            let workspace = WorkspaceID(rawValue: UUID())
            try await Self.fill(DeviceStateStore(configuration: configuration), workspace)
            let clock = ContinuousClock()
            var times: [Double] = []
            for _ in 0..<Self.openCount {
                let store = DeviceStateStore(configuration: configuration)
                var launch: DeviceStateStore.Launch?
                let duration = try await clock.measure { launch = try await store.open() }
                XCTAssertNotNil(launch?.camera)
                times.append(duration / .milliseconds(1))
            }
            times.sort()
            let line = String(
                format: "device state launch read: median %.2f ms, slowest %.2f ms over %d opens",
                times[times.count / 2],
                times.last ?? 0,
                times.count
            )
            XCTContext.runActivity(named: line) { _ in }
            PerformanceRecord.attach([
                "read.median.ms": times[times.count / 2],
                "read.slowest.ms": times.last ?? 0,
            ])
        #endif
    }

    private static func fill(_ store: DeviceStateStore, _ workspace: WorkspaceID) async throws {
        _ = try await store.open()
        let path = (0..<Limits.maxDepth).map { _ in CardID(rawValue: UUID()) }
        try await store.save(lastWorkspace: workspace, navigationPath: path)
        for index in 0..<cameraCount {
            try await store.save(
                Camera(center: Point(x: Double(index), y: 0), zoom: 1),
                for: CanvasID(rawValue: UUID())
            )
        }
        // The launch reads the camera of the deepest canvas of the path (D-99).
        let deepest = path.last.map(CanvasID.init) ?? CanvasID(workspace)
        try await store.save(Camera(center: .zero, zoom: 2), for: deepest)
    }

    private static func removeFolder(_ folder: URL, _ files: FileManager) {
        do {
            try files.removeItem(at: folder)
        } catch {
            XCTFail("The test folder stays behind: \(error)")
        }
    }
}
