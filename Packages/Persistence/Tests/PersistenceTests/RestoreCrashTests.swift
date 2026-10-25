import Foundation
import Model
import Testing

@testable import Persistence

/// A stop of the process at each step of a restore (D-180). The helper stops itself with
/// SIGKILL after the marker, in the copy, or after the copy. The library then holds the old or
/// the new content, never a mix, and the marker names the pre-restore snapshot, which gives
/// the old content back.
@Suite("Restore crash test", .serialized)
struct RestoreCrashTests {
    /// The strokes of the old library and of the picked snapshot. The picked one is large, so
    /// that its copy runs in many steps of pages.
    static let oldStrokes = 1
    static let newStrokes = 3_000

    @Test("A stop at each step of a restore leaves a library and a way back", arguments: [
        "marker", "copy", "done",
    ])
    func stopAtStep(step: String) async throws {
        let folder = try TemporaryFolder()
        let library = folder.path("library.sqlite")
        let backups = folder.url.appending(path: "Backups", directoryHint: .isDirectory)
        try await Self.fill(library, strokes: Self.oldStrokes, folder: folder.url)
        let picked = try await Self.pickedSnapshot(in: folder)
        let process = Process()
        process.executableURL = try CrashTests.productsFolder()
            .appending(path: "PersistenceCrashHelper")
        process.arguments = [
            "restore", library, folder.url.path(percentEncoded: false),
            backups.path(percentEncoded: false), picked.path(percentEncoded: false), step,
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal, "The helper stopped at \(step)")

        let marker = RestoreMarker(libraryPath: library, backupsFolder: backups)
        let fallback = try #require(marker.snapshot(), "The marker survives the stop")
        let count = try await Self.strokeCount(library, folder: folder.url)
        switch step {
        case "marker": #expect(count == Self.oldStrokes)
        case "done": #expect(count == Self.newStrokes)
        default: #expect(count == Self.oldStrokes || count == Self.newStrokes, "\(count)")
        }
        // The way back of a launch whose library does not open: the snapshot of the marker.
        let repository = Self.repository(library, folder: folder.url)
        _ = try await repository.open { _ in }
        let checked = try await SnapshotImport(temporaryFolder: folder.url).copyAndCheck(fallback)
        try await repository.restore(from: checked, stop: RestoreStop())
        let restored = try await Self.strokeCount(library, folder: folder.url)
        #expect(restored == Self.oldStrokes, "The way back gives the old content")
        try marker.remove()
        #expect(marker.snapshot() == nil)
    }

    private static func repository(_ path: String, folder: URL) -> SQLiteLibraryRepository {
        SQLiteLibraryRepository(
            configuration: SQLiteLibraryRepository.Configuration(
                databasePath: path,
                temporaryFolder: folder,
                device: Values.device,
                wallClock: SystemWallClock(),
                timer: ContinuousSaveTimer()
            )
        ) { _ in }
    }

    /// Makes a library at `path` with `strokes` strokes of 300 points on one canvas.
    private static func fill(_ path: String, strokes: Int, folder: URL) async throws {
        let repository = Self.repository(path, folder: folder)
        _ = try await repository.open { _ in }
        let points = InkPoints(
            (0..<300).map { InkPoint(x: Float($0), y: Float($0 % 7), force: 0.5, time: 0) }
        )
        let rows = (0..<strokes).map { _ in
            LibraryChange.stroke(
                Stroke(
                    id: StrokeID(rawValue: UUID()),
                    canvasID: Values.canvas,
                    created: Values.early,
                    origin: .zero,
                    width: 2,
                    points: points
                )
            )
        }
        try await repository.send(rows)
        try await repository.saveNow()
        await repository.close()
    }

    /// A snapshot of a library with `newStrokes` strokes.
    private static func pickedSnapshot(in folder: TemporaryFolder) async throws -> URL {
        let other = folder.url.appending(path: "Other", directoryHint: .isDirectory)
        try FileManager().createDirectory(at: other, withIntermediateDirectories: true)
        let path = other.appending(path: "library.sqlite").path(percentEncoded: false)
        try await Self.fill(path, strokes: Self.newStrokes, folder: other)
        let writer = SnapshotWriter(
            configuration: SnapshotWriter.Configuration(
                databasePath: path,
                temporaryFolder: other,
                backupsFolder: other.appending(path: "Picked", directoryHint: .isDirectory),
                wallClock: SystemWallClock(),
                timeZone: .gmt
            )
        )
        return try await writer.writeSnapshotNow()
    }

    private static func strokeCount(_ path: String, folder: URL) async throws -> Int {
        let repository = Self.repository(path, folder: folder)
        _ = try await repository.open { _ in }
        let content = try await repository.content(of: Values.canvas)
        await repository.close()
        return content.strokes.count
    }
}
