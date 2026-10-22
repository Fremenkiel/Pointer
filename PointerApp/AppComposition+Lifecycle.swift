import Geometry
import Model
import Persistence
import UIKit

extension AppComposition {
    /// The time without input before the app counts as idle: 5 seconds, the start value of
    /// storage.md section 7.2.
    static let idleInterval: TimeInterval = 5

    /// Writes the camera of a canvas when it comes to rest (D-53).
    func save(_ camera: Camera, for canvasID: CanvasID) {
        guard let deviceStore else { return }
        let logger = logger
        Task {
            do {
                try await deviceStore.save(camera, for: canvasID)
            } catch {
                logger.error("The camera was not saved: \(error)")
            }
        }
    }

    /// Shows a fault of the library. Three failed saves in a row stop the pen until a save works
    /// again (storage.md section 4).
    func handle(_ fault: LibraryFault) {
        switch fault {
        case .savesFailing:
            areSavesFailing = true
            container.canvas?.isEditingEnabled = false
            container.showMessage(AppStrings.savesFailing)
        case .savesRecovered:
            areSavesFailing = false
            container.canvas?.isEditingEnabled = !isReadOnly
        case .rowsSkipped:
            container.showMessage(AppStrings.rowsSkipped)
        }
    }

    /// Writes the pending rows, the last workspace, and the camera at the move to the
    /// background, with extra time from the system (storage.md section 4, D-53).
    func enterBackground() {
        // A running text edit records its step now, so that its rows join the save (D-86).
        container.canvas?.finishTextEdit()
        // A pending card joins the canvas, so that its row joins the save too (D-123).
        container.canvas?.placePendingCard()
        stopIdleTimer()
        endBackgroundTask()
        let expire: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.endBackgroundTask() }
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Final save",
            expirationHandler: expire
        )
        let repository = repository
        let deviceStore = deviceStore
        let workspace = selector?.current?.id
        let cards = path?.workspace == workspace ? path?.cards ?? [] : []
        let camera = container.canvas.map { ($0.camera, $0.canvasID) }
        let logger = logger
        Task {
            do {
                try await repository?.saveNow()
                try await deviceStore?.save(lastWorkspace: workspace, navigationPath: cards)
                if let (camera, canvasID) = camera {
                    try await deviceStore?.save(camera, for: canvasID)
                }
            } catch {
                logger.error("The final save failed: \(error)")
            }
            endBackgroundTask()
        }
    }

    /// Ends the extra time of the final save, if it runs.
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    /// Starts the check for an idle moment while the app is active (storage.md section 7.2).
    func startIdleTimer() {
        guard idleTimer == nil else { return }
        let tick: @Sendable (Timer) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        idleTimer = Timer.scheduledTimer(
            withTimeInterval: Self.idleInterval,
            repeats: true,
            block: tick
        )
    }

    /// Stops the check, because the app does not make a snapshot in the background (D-32).
    func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    /// Sends the idle signal to the snapshot writer after 5 seconds without input and with no
    /// pending rows. The writer makes a snapshot only if the newest one is older than 24 hours.
    private func checkIdle() {
        let quiet = ProcessInfo.processInfo.systemUptime - window.lastInputTime
        guard quiet >= Self.idleInterval, !isSnapshotRunning, let repository, let writer else {
            return
        }
        isSnapshotRunning = true
        let logger = logger
        Task {
            if await repository.pendingCount == 0 {
                do {
                    try await writer.appIsIdle()
                } catch {
                    logger.error("The daily snapshot failed: \(error)")
                }
            }
            isSnapshotRunning = false
        }
    }
}
