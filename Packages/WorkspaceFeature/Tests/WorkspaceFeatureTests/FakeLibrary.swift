import Foundation
import Model
import WorkspaceFeature

/// A library in memory for the selector tests. It can fail on demand.
actor FakeLibrary: LibraryRepository {
    private(set) var stored: [Workspace] = []
    private(set) var deleted: [WorkspaceID] = []
    private(set) var createCalls = 0
    private var failure: ModelError?

    init(_ workspaces: [Workspace] = []) {
        stored = workspaces
    }

    func fail(with error: ModelError?) { failure = error }

    func workspaces() throws(ModelError) -> [Workspace] {
        if let failure { throw failure }
        return stored.sorted { $0.sortKey < $1.sortKey }
    }

    func create(_ workspace: Workspace) throws(ModelError) {
        createCalls += 1
        if let failure { throw failure }
        stored.append(workspace)
    }

    func rename(_ id: WorkspaceID, to title: String, modified: HybridTimestamp) throws(ModelError) {
        if let failure { throw failure }
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
        if let failure { throw failure }
        stored.removeAll { $0.id == id }
        deleted.append(id)
    }

    func content(of canvasID: CanvasID) throws(ModelError) -> CanvasContent {
        CanvasContent(canvasID: canvasID)
    }

    func send(_ changes: [LibraryChange]) throws(ModelError) {}

    func requestSave() {}

    func saveNow() throws(ModelError) {}
}

/// Makes IDs, clock values, and workspaces for the tests (TEST-04: no real clock).
@MainActor
final class SelectorFixture {
    let library: FakeLibrary
    private(set) var switches: [WorkspaceID] = []
    private var counter: UInt8 = 0
    private var clock = HybridClock(device: SelectorFixture.device, wallClock: FixedClock())
    static let device = DeviceID(
        rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    init(_ workspaces: [Workspace] = []) {
        library = FakeLibrary(workspaces)
    }

    lazy var model = WorkspaceSelectorModel(
        dependencies: WorkspaceSelectorModel.Dependencies(
            repository: library,
            makeTimestamp: { [unowned self] in timestamp() },
            makeWorkspaceID: { [unowned self] in nextID() },
            onSwitch: { [unowned self] in record($0) }
        )
    )

    func nextID() -> WorkspaceID {
        counter += 1
        return Self.id(200 &+ counter)
    }

    func timestamp() -> HybridTimestamp { clock.now() }

    func record(_ workspace: Workspace) { switches.append(workspace.id) }

    static func id(_ byte: UInt8) -> WorkspaceID {
        WorkspaceID(rawValue: UUID(uuid: (5, byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    static func workspace(_ byte: UInt8, _ title: String, key: String) throws -> Workspace {
        try Workspace(
            id: id(byte),
            meta: RecordMeta(created: HybridTimestamp(wallMillis: 1, counter: 0, device: device)),
            title: title,
            sortKey: FractionalIndex(rawValue: key)
        )
    }

    struct FixedClock: WallClock {
        func nowMillis() -> UInt64 { 1_700_000_000_000 }
    }
}
