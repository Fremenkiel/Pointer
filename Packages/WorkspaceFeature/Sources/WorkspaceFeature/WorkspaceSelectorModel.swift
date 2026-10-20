import Model
import Observation

/// The state and the actions of the workspace selector (WS-01 to WS-04, D-52).
///
/// It keeps the live workspaces in the order of their sort keys. Each change goes to the library
/// at once. The canvas of the current workspace is the job of the app, which `onSwitch` tells.
@MainActor
@Observable
public final class WorkspaceSelectorModel {
    /// The services of the selector. `PointerApp` makes them (ARCH-05).
    public struct Dependencies {
        /// The library.
        public let repository: any LibraryRepository
        /// Returns a new clock value of the shared clock of the app.
        public let makeTimestamp: @MainActor () -> HybridTimestamp
        /// Returns a new workspace ID.
        public let makeWorkspaceID: @MainActor () -> WorkspaceID
        /// Receives the new current workspace.
        public let onSwitch: @MainActor (Workspace) -> Void
        /// Tells the app that a workspace is deleted, so that it drops what it keeps of it.
        public let onDelete: @MainActor (WorkspaceID) -> Void

        /// Makes the dependencies.
        public init(
            repository: any LibraryRepository,
            makeTimestamp: @escaping @MainActor () -> HybridTimestamp,
            makeWorkspaceID: @escaping @MainActor () -> WorkspaceID,
            onSwitch: @escaping @MainActor (Workspace) -> Void,
            onDelete: @escaping @MainActor (WorkspaceID) -> Void = { _ in }
        ) {
            self.repository = repository
            self.makeTimestamp = makeTimestamp
            self.makeWorkspaceID = makeWorkspaceID
            self.onSwitch = onSwitch
            self.onDelete = onDelete
        }
    }

    /// The live workspaces in the order of the selector.
    public private(set) var workspaces: [Workspace] = []
    /// The workspace that the canvas shows.
    public private(set) var current: Workspace?
    /// The message that the selector shows, if any.
    public private(set) var message: WorkspaceMessage?

    @ObservationIgnored private let dependencies: Dependencies

    /// Makes a selector without workspaces. `start(lastWorkspace:)` loads them.
    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// True if the library has room for one more workspace.
    public var canCreate: Bool { workspaces.count < Limits.maxWorkspaces }

    /// Loads the workspaces and opens the last one (WS-04). At the first launch, it makes a
    /// workspace named "Workspace" (D-52). An unknown last workspace opens the first one.
    public func start(lastWorkspace: WorkspaceID?) async {
        do {
            workspaces = try await dependencies.repository.workspaces()
        } catch {
            message = WorkspaceMessage(error)
            return
        }
        guard let first = workspaces.first else {
            await createDefaultWorkspace()
            return
        }
        open(workspaces.first { $0.id == lastWorkspace } ?? first)
    }

    /// Opens the workspace with `id`.
    ///
    /// - Precondition: The selector lists the workspace.
    public func select(_ id: WorkspaceID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else {
            preconditionFailure("Workspace \(id) is not in the selector")
        }
        open(workspace)
    }

    /// Makes a workspace at the end of the list and opens it. At the limit, it shows a message
    /// and does nothing (WS-02).
    public func create(title: String) async {
        guard canCreate else {
            message = .limitReached
            return
        }
        do {
            let workspace = try Workspace(
                id: dependencies.makeWorkspaceID(),
                meta: RecordMeta(created: dependencies.makeTimestamp()),
                title: title,
                sortKey: try FractionalIndex.between(workspaces.last?.sortKey, nil)
            )
            try await dependencies.repository.create(workspace)
            workspaces.append(workspace)
            open(workspace)
        } catch {
            message = WorkspaceMessage(error)
        }
        assert(workspaces.count <= Limits.maxWorkspaces, "The selector lists too many workspaces")
    }

    /// Gives a workspace a new title. The title is trimmed (WS-02).
    ///
    /// - Precondition: The selector lists the workspace.
    public func rename(_ id: WorkspaceID, to title: String) async {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else {
            preconditionFailure("Workspace \(id) is not in the selector")
        }
        do {
            let old = workspaces[index]
            let modified = dependencies.makeTimestamp()
            let meta = RecordMeta(created: old.meta.created, modified: modified, isDeleted: false)
            let renamed = try Workspace(id: id, meta: meta, title: title, sortKey: old.sortKey)
            try await dependencies.repository.rename(id, to: renamed.title, modified: modified)
            workspaces[index] = renamed
            if current?.id == id { current = renamed }
        } catch {
            message = WorkspaceMessage(error)
        }
    }

    /// Deletes a workspace after the confirmation of the view (WS-03, D-11). If it was the
    /// current one, the first workspace opens, or a new one if none is left (D-52).
    ///
    /// - Precondition: The selector lists the workspace.
    public func delete(_ id: WorkspaceID) async {
        precondition(workspaces.contains { $0.id == id }, "Workspace \(id) is not in the selector")
        do {
            try await dependencies.repository.delete(id, modified: dependencies.makeTimestamp())
        } catch {
            message = WorkspaceMessage(error)
            return
        }
        workspaces.removeAll { $0.id == id }
        dependencies.onDelete(id)
        guard current?.id == id else { return }
        if let first = workspaces.first {
            open(first)
        } else {
            await createDefaultWorkspace()
        }
    }

    /// Hides the message.
    public func dismissMessage() {
        message = nil
    }

    private func createDefaultWorkspace() async {
        await create(title: WorkspaceStrings.defaultTitle)
    }

    private func open(_ workspace: Workspace) {
        current = workspace
        dependencies.onSwitch(workspace)
    }
}
