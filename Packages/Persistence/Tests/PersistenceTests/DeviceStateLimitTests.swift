import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

/// The limits of the device state at the bound and one step past it (TEST-06).
@Suite("Device state limits")
struct DeviceStateLimitTests {
    @Test(
        "A camera at a zoom bound loads, and one just past it reads as no camera",
        arguments: [
            (Limits.minZoom, true), (Limits.maxZoom, true),
            (Limits.minZoom.nextDown, false), (Limits.maxZoom.nextUp, false),
        ]
    )
    func zoomBound(zoom: Double, loads: Bool) async throws {
        let folder = try TemporaryFolder()
        let store = DeviceStateStoreTests.store(folder)
        _ = try await store.open()
        try await store.save(Camera(center: .zero, zoom: Limits.standardZoom), for: Values.canvas)
        // The value goes past the check of the table, as a damaged file can hold it.
        let writer = try SQLiteConnection(path: folder.path("device.sqlite"), mode: .readWrite)
        try writer.execute("PRAGMA ignore_check_constraints = ON")
        let update = try writer.prepare("UPDATE camera SET zoom = ?")
        try update.bind(zoom, at: 1)
        try LibraryStatements.run(update)
        let camera = try await store.camera(for: Values.canvas)
        #expect((camera?.zoom == zoom) == loads, "Zoom \(zoom)")
        #expect((camera == nil) == !loads, "Zoom \(zoom)")
    }

    @Test("A stored path of the depth limit loads, and one card more starts a new state")
    func pathDepth() async throws {
        for depth in [Limits.maxDepth, Limits.maxDepth + 1] {
            let folder = try TemporaryFolder()
            let first = DeviceStateStoreTests.store(folder)
            _ = try await first.open()
            let path = (0..<Limits.maxDepth).map { _ in CardID(rawValue: UUID()) }
            try await first.save(lastWorkspace: Values.workspaceID, navigationPath: path)
            await first.close()
            // A path past the limit can only come from a damaged file: 16 bytes per card.
            let writer = try SQLiteConnection(path: folder.path("device.sqlite"), mode: .readWrite)
            let update = try writer.prepare(
                "UPDATE device SET value = randomblob(?) WHERE key = 'navigationPath'"
            )
            try update.bind(Int64(16 * depth), at: 1)
            try LibraryStatements.run(update)
            let launch = try await DeviceStateStoreTests.store(folder).open()
            #expect(launch.isNew == (depth > Limits.maxDepth), "Depth \(depth)")
            #expect(launch.state.navigationPath.count == (depth > Limits.maxDepth ? 0 : depth))
        }
    }
}
