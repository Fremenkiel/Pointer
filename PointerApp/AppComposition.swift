import BackupFeature
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
    /// The root view controller that holds the screens.
    let container: AppViewController
    /// The window that notes the time of the last touch.
    let window: InputTrackingWindow
    /// The defaults that hold the launch arguments.
    let defaults: UserDefaults
    /// The logger of the app.
    let logger = Logger(subsystem: "dk.saarikivi.pointer", category: "App")
    /// The library, or `nil` before it opens or after it fails.
    var repository: SQLiteLibraryRepository?
    /// The device state store, or `nil` before it opens.
    var deviceStore: DeviceStateStore?
    /// The snapshot writer, or `nil` before the library opens.
    var writer: SnapshotWriter?
    /// The clock of the edits, or `nil` before the device state loads.
    var clock: AppClock?
    /// The model of the workspace selector, or `nil` before the library opens.
    var selector: WorkspaceSelectorModel?
    /// The undo history of each canvas while the app runs, across workspace switches (D-12).
    let sessions = CanvasSessions()
    /// The camera of the last workspace from the launch read. The first canvas uses it.
    var launchCamera: (canvas: CanvasID, camera: Camera)?
    /// The stored path of the last workspace from the launch read (WS-04, D-112).
    var launchPath: NavigationPath?
    /// The path of the canvas on the screen, or `nil` before the first open (architecture.md
    /// 6.4).
    var path: NavigationPath?
    /// The last path of each workspace in this run, so a switch back opens its deepest canvas.
    var paths: [WorkspaceID: NavigationPath] = [:]
    /// The open of a card or the leave that runs, or `nil` (D-98).
    var opening: CardOpening?
    /// `true` if the library opens read-only.
    var isReadOnly = false
    /// `true` while the saves fail.
    var areSavesFailing = false
    private var hasFilled = false
    /// Fires when the app is idle, or `nil`.
    var idleTimer: Timer?
    /// `true` while a snapshot runs.
    var isSnapshotRunning = false
    /// True while a restore or "Back up now" runs. The screen then takes no input, and no
    /// edit, command, open, or leave starts (D-169).
    var isLibraryBusy = false
    /// True after `closeScreens()`. A closed composition starts no idle timer, also when the
    /// scene becomes active during a restore (review after M9).
    var isClosed = false
    /// The card previews of the child canvases (D-97), or `nil` before the launch.
    var previewStore: PreviewStore?
    /// The one offscreen renderer of the previews of all canvases, so that they share one
    /// `InkResources` (D-157).
    let previewMaker = PreviewMaker()
    /// The load of the canvas of the last switch, or `nil`.
    var loadTask: Task<Void, Never>?
    /// Runs with the canvas of each load that starts. Only the tests set it (F-13).
    var onLoadStarted: ((CanvasID) -> Void)?
    /// The places of the files that `start()` opens, or `nil` for the folders of the app. Tests
    /// give a temporary folder.
    let fileLocations: AppFiles?
    /// The files that `start()` opened, or `nil` before the launch.
    var openedFiles: AppFiles?
    /// Hands the app to a new composition after a restore (D-148).
    var onReplace: ((Handoff) -> Void)?
    /// The extra time in the background for a restore (D-164). Tests give their own.
    var backgroundTime: any BackgroundTime = SystemBackgroundTime()
    /// The running daily snapshot, or `nil`. The close waits for it.
    var snapshotTask: Task<Void, Never>?
    /// True while the share sheet of "Back up now" shows. No idle snapshot starts then.
    var isSharing = false
    /// The snapshot that the share sheet shows, or `nil`.
    var sharedSnapshot: URL?

    /// Makes the composition. `start(after:)` opens the files.
    init(
        window: InputTrackingWindow,
        container: AppViewController,
        defaults: UserDefaults,
        files: AppFiles? = nil
    ) {
        self.window = window
        self.container = container
        self.defaults = defaults
        fileLocations = files
    }

    /// Opens the files, makes the clock, and opens the last workspace at its last camera
    /// (WS-04). After a restore, `handoff` gives the clock of the old composition (D-152), a
    /// message, and the way back if the restored library does not open (D-20). A failure
    /// shows a message and leaves the empty screen.
    func start(after handoff: Handoff? = nil) async {
        do {
            let files = try fileLocations ?? AppFiles.make(FileManager.default)
            openedFiles = files
            previewStore = PreviewStore(folder: files.previews)
            let device = try await openDeviceState(files)
            guard
                let library = try await openLibrary(
                    files,
                    device: device.state.deviceID,
                    handoff: handoff
                )
            else { return }
            let last = [library.lastTimestamp, handoff?.lastClock].compactMap { $0 }.max()
            makeClock(device: device.state.deviceID, last: last)
            isReadOnly = library.isReadOnly
            if isReadOnly { container.showMessage(AppStrings.readOnly) }
            if let workspace = device.state.lastWorkspace {
                let stored = try NavigationPath(
                    workspace: workspace,
                    cards: device.state.navigationPath
                )
                launchPath = stored
                if let camera = device.camera { launchCamera = (stored.currentCanvas, camera) }
            }
            await startSelector(lastWorkspace: device.state.lastWorkspace)
            if let message = handoff?.message { container.showMessage(message) }
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

    /// Opens the library. If a restored library does not open, it restores the pre-restore
    /// snapshot of `handoff`, which hands the app to a new composition (task 2.2, item 4).
    ///
    /// - Returns: The launch, or `nil` after the way back.
    private func openLibrary(
        _ files: AppFiles,
        device: DeviceID,
        handoff: Handoff?
    ) async throws -> LibraryLaunch? {
        do {
            return try await openLibrary(files, device: device)
        } catch {
            guard let handoff, let fallback = handoff.fallback else { throw error }
            logger.fault("The restored library did not open: \(error)")
            await deviceStore?.close()
            guard await undoRestore(from: fallback, files: files, handoff: handoff) else {
                throw error
            }
            return nil
        }
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
        container.showSelector(model, commands: libraryCommands())
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
        let cards = storedPath(of: workspace.id)
        let deviceStore = deviceStore
        let logger = logger
        Task {
            do {
                try await deviceStore?.save(lastWorkspace: workspace.id, navigationPath: cards)
            } catch {
                logger.error("The last workspace was not saved: \(error)")
            }
        }
        // A newer switch makes the older load useless (F-13), also the load of an open.
        cancelNavigation()
        loadTask?.cancel()
        loadTask = Task { await openCanvas(of: workspace) }
    }

    private func openCanvas(of workspace: Workspace) async {
        guard let repository else { return }
        do {
            guard !Task.isCancelled else { return }
            // A card of the stored path can be deleted, so the path is cut there (D-112).
            let path = try await repository.validPath(
                storedPath(of: workspace.id),
                in: workspace.id
            )
            // The canvas is on the screen already, with its history (F-02).
            guard container.canvas?.canvasID != path.currentCanvas else { return }
            // A child on the screen stays until its preview renders (D-111).
            await writeShownPreview()
            onLoadStarted?(path.currentCanvas)
            let content = try await repository.content(of: path.currentCanvas)
            let camera = try await storedCamera(for: path.currentCanvas)
            // A later switch may have started while the content loaded.
            guard !Task.isCancelled, selector?.current?.id == workspace.id else { return }
            try show(path, content: content, camera: camera)
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
    func fillStrokes(canvasID: CanvasID, saved: Int) -> [Stroke] {
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
