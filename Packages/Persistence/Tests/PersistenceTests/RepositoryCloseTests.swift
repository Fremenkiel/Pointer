import Foundation
import Model
import Testing
import os

@testable import Persistence

/// The close of the repository and a second open (task 1.1 of docs/m9-plan.md, D-148).
@Suite("Close of the repository")
struct RepositoryCloseTests {
    @Test("A closed library refuses a send and opens again with its rows")
    func closeAndOpenAgain() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.stroke(Values.stroke(1))])
        try await repository.saveNow()
        await repository.close()
        await #expect(throws: ModelError.self) {
            try await repository.send([.stroke(Values.stroke(2))])
        }
        _ = try await repository.open { _ in }
        let content = try await repository.content(of: Values.canvas)
        #expect(content.strokes.count == 1)
        await repository.close()
    }

    @Test("A failed open drops its connection, so no write reaches the file")
    func failedOpenWritesNothing() async throws {
        let harness = try RepositoryHarness()
        try await Self.damageLastTimestamp(harness)
        let repository = harness.make()
        await #expect(throws: ModelError.self) { _ = try await repository.open { _ in } }
        await #expect(throws: ModelError.self) {
            try await repository.send([.stroke(Values.stroke(1))])
        }
        #expect(try harness.reader().integer("SELECT count(*) FROM stroke") == 0)
    }

    @Test("A failed open leaves the library closed, so the open can run again")
    func failedOpenCanRunAgain() async throws {
        let harness = try RepositoryHarness()
        try await Self.damageLastTimestamp(harness)
        let repository = harness.make()
        await #expect(throws: ModelError.self) { _ = try await repository.open { _ in } }
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute("DELETE FROM library WHERE key = 'lastTimestamp'")
        let launch = try await repository.open { _ in }
        #expect(!launch.isReadOnly)
        await repository.close()
    }

    @Test("A close waits for the running checkpoint")
    func closeWaitsForCheckpoint() async throws {
        let harness = try RepositoryHarness()
        let isBlocked = OSAllocatedUnfairLock(initialState: true)
        let gate = DispatchSemaphore(value: 0)
        let hasStarted = OSAllocatedUnfairLock(initialState: false)
        let repository = harness.make(beforeCheckpoint: {
            guard isBlocked.withLock({ $0 }) else { return }
            hasStarted.withLock { $0 = true }
            gate.wait()
        })
        _ = try await repository.open { _ in }
        let saves = try await RepositoryCheckpointTests.fill(
            repository,
            toPages: SQLiteLibraryRepository.checkpointPages
        )
        for _ in 0..<1_000 where !hasStarted.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(hasStarted.withLock { $0 })
        let isClosed = OSAllocatedUnfairLock(initialState: false)
        let close = Task {
            await repository.close()
            isClosed.withLock { $0 = true }
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!isClosed.withLock { $0 })
        isBlocked.withLock { $0 = false }
        gate.signal()
        await close.value
        let count = try harness.reader().integer("SELECT count(*) FROM stroke")
        #expect(count == Int64(saves * RepositoryCheckpointTests.strokesPerSave))
        _ = try await repository.open { _ in }
        await repository.close()
    }

    /// Makes a library whose `lastTimestamp` row does not decode, a way to a failed open.
    private static func damageLastTimestamp(_ harness: RepositoryHarness) async throws {
        let repository = try await harness.open()
        await repository.close()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute("UPDATE library SET value = 'damaged' WHERE key = 'lastTimestamp'")
    }
}
