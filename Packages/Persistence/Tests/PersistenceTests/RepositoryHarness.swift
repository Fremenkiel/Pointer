import Foundation
import Model
import os

@testable import Persistence

/// A repository on a library file in its own temporary folder, with a manual timer, a fixed
/// wall clock, and a stream of the faults that it reports.
struct RepositoryHarness {
    static let now: UInt64 = 1_700_000_000_000

    let folder: TemporaryFolder
    let timer = ManualSaveTimer()
    let faults: AsyncStream<LibraryFault>
    private let faultSink: AsyncStream<LibraryFault>.Continuation

    init(folder: TemporaryFolder? = nil) throws {
        self.folder = try folder ?? TemporaryFolder()
        (faults, faultSink) = AsyncStream.makeStream(of: LibraryFault.self)
    }

    var path: String { folder.path("library.sqlite") }

    /// Makes a repository on the library file. It is not open yet.
    func make(
        wallMillis: UInt64 = Self.now,
        failSwitch: FailSwitch? = nil,
        migrations: [Migration] = Migration.library,
        usesCheckpointer: Bool = true,
        beforeCheckpoint: (@Sendable () -> Void)? = nil
    ) -> SQLiteLibraryRepository {
        let configuration = configuration(wallMillis: wallMillis)
        let sink = faultSink
        var hook: (@Sendable () throws(PersistenceError) -> Void)?
        if let failSwitch {
            hook = { @Sendable () throws(PersistenceError) in try failSwitch.check() }
        }
        return SQLiteLibraryRepository(
            configuration: configuration,
            onFault: { sink.yield($0) },
            beforeCommit: hook,
            migrations: migrations,
            usesCheckpointer: usesCheckpointer,
            beforeCheckpoint: beforeCheckpoint
        )
    }

    /// The configuration of the repositories of the harness.
    func configuration(wallMillis: UInt64 = Self.now) -> SQLiteLibraryRepository.Configuration {
        SQLiteLibraryRepository.Configuration(
            databasePath: path,
            temporaryFolder: folder.url,
            device: Values.device,
            wallClock: FixedWallClock(millis: wallMillis),
            timer: timer
        )
    }

    /// Makes a repository with the public initializer of the app, with no test hook.
    func makeAsTheApp() -> SQLiteLibraryRepository {
        let sink = faultSink
        return SQLiteLibraryRepository(configuration: configuration(), onFault: { sink.yield($0) })
    }

    /// Makes and opens a repository without a pre-migration snapshot.
    func open(
        wallMillis: UInt64 = Self.now,
        failSwitch: FailSwitch? = nil
    ) async throws -> SQLiteLibraryRepository {
        let repository = make(wallMillis: wallMillis, failSwitch: failSwitch)
        _ = try await repository.open { _ in }
        return repository
    }

    /// Opens a second, read-only connection to look at the file.
    func reader() throws -> SQLiteConnection {
        try SQLiteConnection(path: path, mode: .readOnly)
    }
}

/// Makes the transaction fail between the last row and `COMMIT` while it is on.
final class FailSwitch: Sendable {
    private let isOn = OSAllocatedUnfairLock(initialState: false)

    func set(_ value: Bool) { isOn.withLock { $0 = value } }

    func check() throws(PersistenceError) {
        guard isOn.withLock({ $0 }) else { return }
        throw .sqlite(code: 10, message: "injected failure before COMMIT")
    }
}

extension Values {
    /// A stroke with the creation time `millis`, so a test can tell when it was sent.
    static func stroke(_ byte: UInt8, millis: UInt64) -> Stroke {
        Stroke(
            id: StrokeID(rawValue: UUID(uuid: (4, byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            canvasID: canvas,
            created: HybridTimestamp(wallMillis: millis, counter: 0, device: device),
            origin: .zero,
            width: 2,
            points: points
        )
    }
}
