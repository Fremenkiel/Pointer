import Foundation
import Model
import Synchronization

/// A serial executor that keeps each job until the test runs it, so that a test can run the
/// jobs of an actor in another order than they came (SE-0392, D-184).
final class GatedExecutor: SerialExecutor, Sendable {
    private let jobs = Mutex<[UnownedJob]>([])
    /// The thread of the jobs that the test releases, one at a time, off the main actor.
    private let queue = DispatchQueue(label: "GatedExecutor")

    /// The number of waiting jobs.
    var count: Int { jobs.withLock { $0.count } }

    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        jobs.withLock { $0.append(unowned) }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    /// Runs the waiting job at `index` on the queue of the executor.
    ///
    /// - Precondition: A job waits at `index`.
    func run(at index: Int) {
        let job = jobs.withLock { list -> UnownedJob in
            precondition(list.indices.contains(index), "No job waits at \(index)")
            return list.remove(at: index)
        }
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }

    /// Waits on the main actor until `count` jobs wait, at most 2 s.
    @MainActor
    func waitForJobs(_ count: Int) async throws {
        for _ in 0..<2_000 where self.count < count {
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

/// A library of workspaces in memory whose jobs run on a `GatedExecutor`.
actor GatedLibrary: LibraryRepository {
    private(set) var stored: [Workspace]
    private let executor: GatedExecutor

    init(_ workspaces: [Workspace], executor: GatedExecutor) {
        stored = workspaces
        self.executor = executor
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func workspaces() throws(ModelError) -> [Workspace] {
        stored.sorted { $0.sortKey < $1.sortKey }
    }

    func create(_ workspace: Workspace) throws(ModelError) {
        stored.append(workspace)
    }

    func rename(_ id: WorkspaceID, to title: String, modified: HybridTimestamp) throws(ModelError) {
        guard let index = stored.firstIndex(where: { $0.id == id }) else {
            throw .storageFailed(reason: "missing")
        }
        let old = stored[index]
        stored[index] = try Workspace(
            id: id,
            meta: RecordMeta(created: old.meta.created, modified: modified, isDeleted: false),
            title: title,
            sortKey: old.sortKey
        )
    }

    func delete(_ id: WorkspaceID, modified: HybridTimestamp) throws(ModelError) {
        stored.removeAll { $0.id == id }
    }

    func content(of canvasID: CanvasID) throws(ModelError) -> CanvasContent {
        CanvasContent(canvasID: canvasID)
    }

    func validPath(
        _ cards: [CardID],
        in workspace: WorkspaceID
    ) throws(ModelError) -> NavigationPath {
        try NavigationPath(workspace: workspace, cards: Array(cards.prefix(Limits.maxDepth)))
    }

    func send(_ changes: [LibraryChange]) throws(ModelError) {}

    func requestSave() {}

    func saveNow() throws(ModelError) {}
}
