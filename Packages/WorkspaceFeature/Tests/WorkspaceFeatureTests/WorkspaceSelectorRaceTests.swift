import Foundation
import Model
import Testing

@testable import WorkspaceFeature

/// The selector across the await of a library call (review after M9, section 3.2, item 10). The
/// gated executor runs the jobs of the library in another order than they came (D-184).
@MainActor
@Suite("Workspace selector across an await")
struct WorkspaceSelectorRaceTests {
    private static func model(_ library: GatedLibrary) -> WorkspaceSelectorModel {
        let fixture = SelectorFixture()
        return WorkspaceSelectorModel(
            dependencies: WorkspaceSelectorModel.Dependencies(
                repository: library,
                makeTimestamp: { fixture.timestamp() },
                makeWorkspaceID: { fixture.nextID() },
                onSwitch: { _ in }
            )
        )
    }

    /// Waits up to 2 s for `condition` and records the step that did not end.
    private static func wait(_ step: String, for condition: () -> Bool) async throws {
        for _ in 0..<2_000 where !condition() {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), "\(step) did not end")
    }

    /// Starts the model and runs the job of its load.
    private static func start(
        _ model: WorkspaceSelectorModel,
        executor: GatedExecutor
    ) async throws {
        Task { await model.start(lastWorkspace: nil) }
        try await executor.waitForJobs(1)
        #expect(executor.count == 1, "The load reached the library")
        executor.run(at: 0)
        try await wait("The load") { model.workspaces.count == 3 }
    }

    @Test("A rename that finishes after a delete of an earlier workspace renames its own row")
    func renameAfterDelete() async throws {
        let executor = GatedExecutor()
        let library = GatedLibrary(try WorkspaceSelectorModelTests.three(), executor: executor)
        let model = Self.model(library)
        try await Self.start(model, executor: executor)
        let (first, second) = (model.workspaces[0].id, model.workspaces[1].id)
        Task { await model.rename(second, to: "Renamed") }
        try await executor.waitForJobs(1)
        Task { await model.delete(first) }
        try await executor.waitForJobs(2)
        #expect(executor.count == 2, "The rename and the delete reached the library")
        executor.run(at: 1)
        try await Self.wait("The delete") { model.workspaces.count == 2 }
        executor.run(at: 0)
        try await Self.wait("The rename") { model.workspaces.contains { $0.title == "Renamed" } }
        #expect(model.workspaces.map(\.title) == ["Renamed", "Gamma"])
        // The read of the library is a job of the gated executor too.
        let stored = Task { try await library.workspaces() }
        try await executor.waitForJobs(1)
        executor.run(at: 0)
        #expect(model.workspaces.map(\.id) == (try await stored.value).map(\.id))
    }

    @Test("Two creates before either one finishes get two different sort keys")
    func twoCreates() async throws {
        let executor = GatedExecutor()
        let library = GatedLibrary(try WorkspaceSelectorModelTests.three(), executor: executor)
        let model = Self.model(library)
        try await Self.start(model, executor: executor)
        Task { await model.create(title: "First") }
        try await executor.waitForJobs(1)
        Task { await model.create(title: "Second") }
        try await executor.waitForJobs(2)
        #expect(executor.count == 2, "Both creates reached the library")
        executor.run(at: 1)
        try await Self.wait("The second create") { model.workspaces.count == 4 }
        executor.run(at: 0)
        try await Self.wait("The first create") { model.workspaces.count == 5 }
        let keys = model.workspaces.map(\.sortKey)
        #expect(Set(keys).count == keys.count, "Each workspace has its own key")
        #expect(keys == keys.sorted(), "The list follows the keys")
        #expect(model.workspaces.map(\.title).suffix(2) == ["First", "Second"])
    }
}
