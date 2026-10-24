import CanvasFeature
import Model
import Persistence

/// The close of the composition before a restore (task 2.1 of docs/m9-plan.md, D-148, D-150,
/// D-157). A new composition then opens the files again, as at launch.
extension AppComposition {
    /// Saves the work on the screen before a restore or "Back up now" (D-149): the text edit
    /// ends, a pending card joins the canvas, the canvas sends its rows, and the library writes
    /// them. The canvas takes no new edit until `resumeEditing()` or `endLibraryWork()`.
    ///
    /// - Throws: `ModelError` of the save. The rows then stay pending.
    func saveWorkOnScreen() async throws(ModelError) {
        guard let repository else { throw .storageFailed(reason: "the library is not open") }
        if let canvas = container.canvas {
            canvas.finishTextEdit()
            canvas.placePendingCard()
            canvas.isEditingEnabled = false
            await canvas.flushRows()
        }
        try await repository.saveNow()
    }

    /// Lets the canvas on the screen take edits again after a save, a backup, or a refused
    /// restore.
    func resumeEditing() {
        container.canvas?.isEditingEnabled = canEdit
    }

    /// True if a canvas takes edits: the library is not read-only, saves work, and no restore
    /// or "Back up now" runs.
    var canEdit: Bool { !isReadOnly && !areSavesFailing && !isLibraryBusy }

    /// Starts a restore or "Back up now": the screen takes no input, and the canvas takes no
    /// edit, also no undo from the keyboard, until `endLibraryWork()` (D-169).
    ///
    /// - Returns: `false` if one runs already. The new one then does nothing.
    func beginLibraryWork() -> Bool {
        guard !isLibraryBusy, !isClosed else { return false }
        isLibraryBusy = true
        container.view.isUserInteractionEnabled = false
        container.canvas?.isEditingEnabled = false
        return true
    }

    /// Ends "Back up now" or a restore that did not replace the composition: the screen takes
    /// input, and the canvas takes edits again.
    func endLibraryWork() {
        precondition(isLibraryBusy, "No restore or back-up runs")
        isLibraryBusy = false
        container.view.isUserInteractionEnabled = true
        resumeEditing()
    }

    /// Ends the screens of the run (D-150): the idle timer, a running daily snapshot, the load
    /// of a canvas, an open or a leave, and the canvas screen with its renderer. The undo
    /// histories, the paths, and the stored camera of the launch go. The library stays open.
    func closeScreens() async {
        isClosed = true
        stopIdleTimer()
        await snapshotTask?.value
        loadTask?.cancel()
        loadTask = nil
        cancelNavigation()
        if let canvas = container.canvas {
            // The histories of the old library must not reach the new one (D-150).
            canvas.discardSession()
            container.removeCanvas()
            await canvas.flushRows()
        }
        sessions.removeAll()
        paths = [:]
        path = nil
        launchPath = nil
        launchCamera = nil
        await previewStore?.close()
    }

    /// Closes the composition: `closeScreens()`, a last save, the library, and the device
    /// state. Then the preview cache goes (D-157).
    ///
    /// - Throws: `ModelError` of the last save. The library then stays open.
    func close() async throws(ModelError) {
        await closeScreens()
        try await repository?.saveNow()
        await repository?.close()
        await closeFilesAfterRestore()
    }

    /// Closes the device state and clears the preview cache, after the library closed.
    func closeFilesAfterRestore() async {
        await deviceStore?.close()
        await clearPreviews()
    }

    /// Deletes the files of the preview cache (D-157).
    func clearPreviews() async {
        do {
            try await previewStore?.removeAll()
        } catch {
            logger.error("The preview cache stays after the close: \(error)")
        }
    }
}
