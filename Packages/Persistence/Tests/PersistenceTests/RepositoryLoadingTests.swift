import Foundation
import Model
import Testing

@testable import Persistence

@Suite("Repository loads and workspaces")
struct RepositoryLoadingTests {
    @Test("A corrupt point BLOB skips that stroke, reports it, and the other strokes load")
    func corruptStroke() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send((1...3).map { .stroke(Values.stroke($0, millis: 10)) })
        try await repository.saveNow()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute("PRAGMA ignore_check_constraints = ON")
        try writer.execute(
            "UPDATE stroke SET points = zeroblob(20) WHERE id = X'04020000000000000000000000000000'"
        )

        let content = try await repository.content(of: Values.canvas)
        #expect(content.strokes.count == 2)
        #expect(content.strokes[Values.stroke(2, millis: 10).id] == nil)
        var faults = harness.faults.makeAsyncIterator()
        #expect(await faults.next() == .rowsSkipped(table: "stroke", count: 1))
    }

    @Test("A load inside the save throttle holds the rows that wait for a save (F-01)")
    func loadHoldsPendingRows() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let first = Values.stroke(1, millis: 10)
        try await repository.send([.stroke(first)])
        try await repository.saveNow()
        let erase = EraseRecord(
            strokeID: first.id,
            erased: Values.late,
            modified: Values.late,
            isDeleted: false
        )
        let textBox = try Values.textBox(5)
        let second = Values.stroke(2, millis: 20)
        try await repository.send([.stroke(second), .erase(erase), .textBox(textBox)])
        #expect(await repository.pendingCount == 3)

        let content = try await repository.content(of: Values.canvas)
        #expect(Array(content.strokes.keys) == [second.id])
        #expect(content.textBoxes[textBox.id] == textBox)
        #expect(await repository.pendingCount == 0)
    }

    @Test("A load whose save of the pending rows fails throws and loads nothing stale (F-01)")
    func loadFailsWithFailedSave() async throws {
        let harness = try RepositoryHarness()
        let failSwitch = FailSwitch()
        let repository = try await harness.open(failSwitch: failSwitch)
        try await repository.send([.stroke(Values.stroke(1, millis: 10))])
        try await repository.saveNow()
        failSwitch.set(true)
        try await repository.send([.stroke(Values.stroke(2, millis: 20))])

        let error = await #expect(throws: ModelError.self) {
            _ = try await repository.content(of: Values.canvas)
        }
        guard case .storageFailed = error else {
            Issue.record("Expected storageFailed, got \(String(describing: error))")
            return
        }
        #expect(await repository.pendingCount == 1)
    }

    @Test("Workspaces are created, renamed with a trim, deleted, and listed in sort order")
    func workspaces() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let second = try Workspace(
            id: Values.id(2),
            meta: Values.meta,
            title: "B",
            sortKey: FractionalIndex(rawValue: "W")
        )
        try await repository.create(second)
        try await repository.create(try Values.workspace(1, title: "A"))
        #expect(try await repository.workspaces().map(\.title) == ["A", "B"])

        try await repository.rename(Values.id(1), to: "  Notes \n", modified: Values.late)
        #expect(try await repository.workspaces().map(\.title) == ["Notes", "B"])
        try await repository.delete(Values.id(1), modified: Values.late)
        #expect(try await repository.workspaces().map(\.id) == [second.id])
        await #expect(throws: ModelError.self) {
            try await repository.rename(Values.id(1), to: "Gone", modified: Values.late)
        }
        await #expect(throws: ModelError.self) {
            try await repository.delete(Values.id(1), modified: Values.late)
        }
        await #expect(throws: ModelError.invalidTitle(length: 0)) {
            try await repository.rename(Values.id(2), to: "  ", modified: Values.late)
        }
    }

    @Test("A second create of the same workspace ID throws, and the first row stays (3.2.4)")
    func createTwice() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.create(try Values.workspace(1, title: "First"))
        await #expect(throws: ModelError.self) {
            try await repository.create(try Values.workspace(1, title: "Second"))
        }
        #expect(try await repository.workspaces().map(\.title) == ["First"])
    }

    @Test("The library takes workspaces up to the limit and refuses one more")
    func workspaceLimit() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute(
            """
            WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000)
            INSERT INTO workspace
            SELECT randomblob(16), 'W', 'V', zeroblob(28), zeroblob(28), 0 FROM n
            """
        )
        #expect(try await repository.workspaces().count == Limits.maxWorkspaces)
        await #expect(throws: ModelError.workspaceLimitReached) {
            try await repository.create(try Values.workspace(1))
        }
        try writer.execute(
            "INSERT INTO workspace VALUES (randomblob(16), 'W', 'V', zeroblob(28), zeroblob(28), 0)"
        )
        #expect(try await repository.workspaces().count == Limits.maxWorkspaces)
        var faults = harness.faults.makeAsyncIterator()
        #expect(await faults.next() == .rowsSkipped(table: "workspace", count: 1))
    }

    @Test("A library with a newer schema opens read-only, reads, and refuses each write")
    func newerSchema() async throws {
        let harness = try RepositoryHarness()
        let first = try await harness.open()
        try await first.create(try Values.workspace())
        try SQLiteConnection(path: harness.path, mode: .readWrite).execute(
            "PRAGMA user_version = 2"
        )

        let repository = harness.make()
        let launch = try await repository.open { _ in }
        #expect(launch.isReadOnly)
        #expect(try await repository.workspaces().count == 1)
        await #expect(throws: ModelError.libraryIsReadOnly) {
            try await repository.send([.stroke(Values.stroke(1, millis: 1))])
        }
        await #expect(throws: ModelError.libraryIsReadOnly) {
            try await repository.create(try Values.workspace(2))
        }
        #expect(try harness.reader().integer("PRAGMA user_version") == 2)
    }

    @Test("A repository that is not open refuses reads and writes")
    func notOpen() async throws {
        let repository = try RepositoryHarness().make()
        await #expect(throws: ModelError.storageFailed(reason: "the library is not open")) {
            try await repository.workspaces()
        }
        await #expect(throws: ModelError.storageFailed(reason: "the library is not open")) {
            try await repository.send([])
        }
        await repository.requestSave()
        try await repository.saveNow()
    }
}
