import CanvasFeature
import Geometry
import Model
import Persistence
import Rendering
import UIKit
import WorkspaceFeature
import os

/// Opens the library, the device state, and the snapshot writer at launch, and connects them
/// with the canvas and the workspace selector (task 3.9 of docs/m3-plan.md, ARCH-01).
@MainActor
final class AppComposition {
    let container: AppViewController
    let window: InputTrackingWindow
    let defaults: UserDefaults
    let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "App")
    var repository: SQLiteLibraryRepository?
    var deviceStore: DeviceStateStore?
    var writer: SnapshotWriter?
    var clock: AppClock?
    var selector: WorkspaceSelectorModel?
    /// The undo history of each canvas while the app runs, across workspace switches (D-12).
    let sessions = CanvasSessions()
    /// The camera of the last workspace from the launch read. The first canvas uses it.
    var launchCamera: (canvas: CanvasID, camera: Camera)?
    var isReadOnly = false
    var areSavesFailing = false
    var hasFilled = false
    var idleTimer: Timer?
    var isSnapshotRunning = false
    var backgroundTask = UIBackgroundTaskIdentifier.invalid
    /// The load of the canvas of the last switch, or `nil`.
    var loadTask: Task<Void, Never>?
    /// Runs with the canvas of each load that starts. Only the tests set it (F-13).
    var onLoadStarted: ((CanvasID) -> Void)?

    /// Makes the composition. `start()` opens the files.
    init(window: InputTrackingWindow, container: AppViewController, defaults: UserDefaults) {
        self.window = window
        self.container = container
        self.defaults = defaults
    }

    /// Opens the files, makes the clock, and opens the last workspace at its last camera
    /// (WS-04). A failure shows a message and leaves the black screen.
    func start() async {
        do {
            let files = try AppFiles.make(FileManager.default)
            let device = try await openDeviceState(files)
            let library = try await openLibrary(files, device: device.state.deviceID)
            makeClock(device: device.state.deviceID, last: library.lastTimestamp)
            isReadOnly = library.isReadOnly
            if isReadOnly { container.showMessage(AppStrings.readOnly) }
            if let workspace = device.state.lastWorkspace, let camera = device.camera {
                launchCamera = (CanvasID(workspace), camera)
            }
            await startSelector(lastWorkspace: device.state.lastWorkspace)
        } catch {
            logger.fault("The launch failed: \(error)")
            container.showMessage(AppStrings.libraryFailed)
        }
    }

    private func openDeviceState(_ files: AppFiles) async throws -> DeviceStateStore.Launch {
        let store = DeviceStateStore(
            configuration: DeviceStateStore.Configuration(
                databasePath: files.device,
                makeDeviceID: {
                    var identifiers = IdentifierFactory(
                        wallClock: SystemWallClock(),
                        random: SystemRandomNumberGenerator()
                    )
                    return identifiers.make()
                }
            )
        )
        deviceStore = store
        return try await store.open()
    }

    private func openLibrary(_ files: AppFiles, device: DeviceID) async throws -> LibraryLaunch {
        let snapshots = SnapshotWriter(
            configuration: SnapshotWriter.Configuration(
                databasePath: files.library,
                temporaryFolder: files.temporary,
                backupsFolder: files.backups,
                wallClock: SystemWallClock(),
                timeZone: .current
            )
        )
        writer = snapshots
        let library = SQLiteLibraryRepository(
            configuration: SQLiteLibraryRepository.Configuration(
                databasePath: files.library,
                temporaryFolder: files.temporary,
                device: device,
                wallClock: SystemWallClock(),
                timer: ContinuousSaveTimer()
            )
        ) { [weak self] fault in self?.handle(fault) }
        repository = library
        return try await library.open { version throws(PersistenceError) in
            try await snapshots.writePreMigrationSnapshot(oldVersion: version)
        }
    }

    /// Makes the one clock of the app. It continues after the largest clock value of the
    /// library, with the device ID of this iPad, also after a restore from another iPad.
    private func makeClock(device: DeviceID, last: HybridTimestamp?) {
        let wallClock = SystemWallClock()
        let continued = last.map {
            HybridTimestamp(wallMillis: $0.wallMillis, counter: $0.counter, device: device)
        }
        clock = AppClock(
            factory: StrokeFactory(
                identifiers: IdentifierFactory(
                    wallClock: wallClock,
                    random: SystemRandomNumberGenerator()
                ),
                clock: HybridClock(device: device, wallClock: wallClock, last: continued)
            )
        )
    }

    private func startSelector(lastWorkspace: WorkspaceID?) async {
        guard let repository, let clock else { preconditionFailure("The library is not open") }
        let model = WorkspaceSelectorModel(
            dependencies: WorkspaceSelectorModel.Dependencies(
                repository: repository,
                makeTimestamp: { clock.now() },
                makeWorkspaceID: { clock.makeIdentifier() },
                onSwitch: { [weak self] workspace in self?.open(workspace) },
                onDelete: { [weak self] id in self?.forgetSession(of: id) }
            )
        )
        selector = model
        container.showSelector(model)
        await model.start(lastWorkspace: lastWorkspace)
    }

    /// Drops the undo history of a deleted workspace. The canvas on the screen keeps none when
    /// it leaves (M-03).
    func forgetSession(of workspace: WorkspaceID) {
        let canvasID = CanvasID(workspace)
        if container.canvas?.canvasID == canvasID { container.canvas?.discardSession() }
        sessions.remove(for: canvasID)
    }

    /// Opens the canvas of a workspace and notes it as the last workspace (D-53).
    func open(_ workspace: Workspace) {
        let deviceStore = deviceStore
        let logger = logger
        Task {
            do {
                try await deviceStore?.save(lastWorkspace: workspace.id, navigationPath: [])
            } catch {
                logger.error("The last workspace was not saved: \(error)")
            }
        }
        // A newer switch makes the older load useless (F-13).
        loadTask?.cancel()
        loadTask = Task { await openCanvas(of: workspace) }
    }

    private func openCanvas(of workspace: Workspace) async {
        guard let repository, let clock else { return }
        let canvasID = workspace.canvasID
        // The canvas is on the screen already, with its history (F-02).
        guard container.canvas?.canvasID != canvasID else { return }
        do {
            guard !Task.isCancelled else { return }
            onLoadStarted?(canvasID)
            let content = try await repository.content(of: canvasID)
            let camera = try await storedCamera(for: canvasID)
            // A later switch may have started while the content loaded.
            guard !Task.isCancelled, selector?.current?.id == workspace.id else { return }
            var dependencies = CanvasDependencies(
                renderer: try CanvasRenderer(
                    configuration: CanvasComposition.rendererConfiguration(defaults)
                ),
                clock: clock,
                content: content
            )
            dependencies.camera = camera
            dependencies.repository = repository
            dependencies.sessions = sessions
            dependencies.transientStrokes = fillStrokes(
                canvasID: canvasID,
                saved: content.strokes.count
            )
            dependencies.onCameraRest = { [weak self] camera in self?.save(camera, for: canvasID) }
            dependencies.onMessage = { [weak self] text in self?.container.showMessage(text) }
            // The new screen reads the sessions, so the old one keeps its steps first (F-02).
            container.canvas?.endSession()
            let canvas = CanvasViewController(dependencies: dependencies)
            canvas.isEditingEnabled = !isReadOnly && !areSavesFailing
            container.show(canvas)
        } catch {
            logger.error("The canvas did not open: \(error)")
            container.showMessage(AppStrings.canvasFailed)
        }
    }

    private func storedCamera(for canvasID: CanvasID) async throws -> Camera? {
        if let launch = launchCamera, launch.canvas == canvasID {
            launchCamera = nil
            return launch.camera
        }
        return try await deviceStore?.camera(for: canvasID)
    }

    /// Returns the fill content of the launch argument, once, for the first canvas (D-55).
    private func fillStrokes(canvasID: CanvasID, saved: Int) -> [Stroke] {
        guard !hasFilled, let clock else { return [] }
        hasFilled = true
        let room = Limits.maxStrokesPerCanvas - saved
        return CanvasComposition.fillStrokes(
            defaults: defaults,
            canvasID: canvasID,
            limit: room,
            factory: &clock.factory
        )
    }
}
