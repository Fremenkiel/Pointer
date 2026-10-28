import CanvasFeature
import Geometry
import Model
import Rendering
import UIKit

/// The navigation in the card tree: the open of a card, the leave, and the path in the device
/// state (architecture.md section 6, CARD-03, CARD-04, WS-04, D-99, D-112).
extension AppComposition {
    /// Returns the stored path of a workspace: its path of this run, the path of the launch for
    /// the last workspace, or an empty path.
    func storedPath(of workspace: WorkspaceID) -> [CardID] {
        if let path = paths[workspace] { return path.cards }
        if let launch = launchPath, launch.workspace == workspace { return launch.cards }
        return []
    }

    /// Opens the child canvas of a card with the animation of D-98: the parent flies until the
    /// card covers the screen, the child loads at the camera of CARD-03 in the same time, and
    /// the child fades in when both are done (architecture.md 6.2, D-99).
    func openChild(_ card: Card) {
        guard !isLibraryBusy, let path, let parent = container.canvas, opening == nil,
            !container.isSwapping,
            !parent.isInCardTransition, parent.canvasID == path.currentCanvas,
            card.canvasID == path.currentCanvas
        else { return }
        let child: NavigationPath
        do {
            child = try path.pushing(card.id)
        } catch {
            logger.error("A card below level 32 does not open: \(error)")
            return
        }
        let opening = CardOpening(target: child)
        self.opening = opening
        parent.beginOpen(of: card) { [weak self] in
            opening.isFlightDone = true
            self?.finishOpen()
        }
        loadTask?.cancel()
        loadTask = Task { await loadChild(of: opening, card: card, parent: parent) }
    }

    /// Loads the child of an open above the parent at opacity 0 and waits for its first frame.
    private func loadChild(
        of opening: CardOpening,
        card: Card,
        parent: CanvasViewController
    ) async {
        // A return that is not a cancel ends the open, so that the next open can start (D-131).
        guard let repository else { return fail(opening, on: parent) }
        let target = opening.target
        do {
            onLoadStarted?(target.currentCanvas)
            let content = try await repository.content(of: target.currentCanvas)
            guard !Task.isCancelled else { return }
            guard
                let canvas = try makeCanvas(
                    target,
                    content: content,
                    camera: content.openCamera,
                    parentCard: card
                )
            else { return fail(opening, on: parent) }
            container.showAbove(canvas)
            opening.added = canvas
            try await CardOpening.waitForFirstFrame(of: canvas)
            opening.canvas = canvas
            finishOpen()
        } catch is CancellationError {
            // A workspace switch cancelled the open, and `cancelNavigation()` cleaned up.
        } catch {
            logger.error("The canvas of a card did not open: \(error)")
            fail(opening, on: parent)
        }
    }

    /// Fades the child in when the flight and its first frame are both done (D-98). Until then,
    /// the screen holds the last frame of the flight.
    private func finishOpen() {
        guard let opening, opening.isFlightDone, let canvas = opening.canvas else { return }
        self.opening = nil
        // A save failure or a restore during the flight changed the edit state of the app, and
        // the child was made before it (review of 2026-10-28).
        canvas.isEditingEnabled = canEdit
        // The child keeps the frozen copy of the parent for its pinch-out exit (D-109).
        container.canvas?.giveParentImage(to: canvas)
        container.completeSwap(to: canvas, duration: CanvasRenderer.crossfadeDuration) {}
        showUpButton(level: opening.target.level)
        remember(opening.target)
    }

    /// Leaves the current card for its parent canvas with the animation of D-98 and D-109:
    /// the child flies to the camera of its open while the parent loads below it, showing the
    /// card alone. Then the child fades out, and the parent flies to the camera of CARD-04.
    func leave() {
        guard !isLibraryBusy, let path, let child = container.canvas, let card = path.cards.last,
            opening == nil,
            !container.isSwapping, !child.isInCardTransition,
            child.canvasID == path.currentCanvas
        else { return }
        let leaving = CardOpening(target: path.popping())
        opening = leaving
        child.prepareLeave { [weak self] in
            leaving.isFlightDone = true
            self?.finishLeave(into: card)
        }
        loadTask?.cancel()
        loadTask = Task { await loadParent(of: leaving, card: card, child: child) }
    }

    /// Leaves the current card after a pinch-out exit (CARD-05): the child already shrank into
    /// its card, so the parent loads below it at the camera of CARD-04, and the child fades out,
    /// which crossfades its image into the preview of the card.
    func leaveByPinch() {
        // The guards of `leave()`: a pinch during a restore starts no load on a library that is
        // about to be replaced (review of 2026-10-28, 3.2.15).
        guard !isLibraryBusy, let path, let child = container.canvas, let card = path.cards.last,
            opening == nil, !container.isSwapping
        else { return }
        let leaving = CardOpening(target: path.popping())
        leaving.isFlightDone = true
        leaving.isPinch = true
        opening = leaving
        loadTask?.cancel()
        loadTask = Task { await loadParent(of: leaving, card: card, child: child) }
    }

    /// Loads the parent of a leave below the child, at the camera where the card covers the
    /// screen with the parent at weight 0, or at the camera of CARD-04 after a pinch-out exit,
    /// and waits for its first frame.
    private func loadParent(
        of leaving: CardOpening,
        card: CardID,
        child: CanvasViewController
    ) async {
        // A return that is not a cancel ends the leave, so that the next open can start (D-131).
        guard let repository else { return fail(leaving, on: child) }
        let target = leaving.target
        do {
            onLoadStarted?(target.currentCanvas)
            let content = try await repository.content(of: target.currentCanvas)
            guard !Task.isCancelled else { return }
            guard let parentCard = content.cards[card] else { return fail(leaving, on: child) }
            let frame = parentCard.frame
            let bounds = container.view.bounds
            let screen = Size(width: bounds.width, height: bounds.height)
            let start =
                leaving.isPinch
                ? Camera(center: frame.center, zoom: Limits.standardZoom)
                : CanvasViewController.coverCamera(of: frame, viewSize: screen)
            guard let canvas = try makeCanvas(target, content: content, camera: start) else {
                return fail(leaving, on: child)
            }
            if !leaving.isPinch { canvas.holdLeave(into: parentCard) }
            leaving.card = parentCard
            renderPreview(of: child, for: parentCard, in: leaving)
            container.showBelow(canvas)
            leaving.added = canvas
            try await CardOpening.waitForFirstFrame(of: canvas)
            leaving.canvas = canvas
            finishLeave(into: card)
        } catch is CancellationError {
            // A workspace switch cancelled the leave, and `cancelNavigation()` cleaned up.
        } catch {
            logger.error("The parent of a card did not open: \(error)")
            fail(leaving, on: child)
        }
    }

    /// Ends an open or a leave that failed: the screen that it added goes, the shown screen
    /// takes input again, and a message shows.
    private func fail(_ failed: CardOpening, on shown: CanvasViewController) {
        guard opening === failed else { return }
        opening = nil
        failed.added.map(container.removeAbove)
        shown.cancelCardTransition()
        container.showMessage(AppStrings.canvasFailed)
    }

    /// Ends a running open or leave before a workspace switch: the screen that it added goes,
    /// so that no hidden screen keeps its renderer, and the next open or leave can start
    /// (WS-02). The switch then replaces the shown screen.
    func cancelNavigation() {
        guard let cancelled = opening else { return }
        opening = nil
        cancelled.added.map(container.removeAbove)
        container.canvas?.cancelCardTransition()
    }

    /// Fades the child out when its flight and the first frame of the parent are both done,
    /// then plays the leave on the parent (D-98).
    func finishLeave(into card: CardID) {
        guard let leaving = opening, leaving.isFlightDone, leaving.isPreviewDone,
            let parent = leaving.canvas, let parentCard = leaving.card, parentCard.id == card
        else { return }
        opening = nil
        parent.isEditingEnabled = canEdit
        if let preview = leaving.preview { parent.showPreview(preview, of: card) }
        let level = leaving.target.level
        let isPinch = leaving.isPinch
        let runLeave: @MainActor () -> Void = {
            if !isPinch { parent.runLeave(into: parentCard) {} }
        }
        container.fadeOut(
            to: parent,
            duration: CanvasRenderer.crossfadeDuration,
            completion: runLeave
        )
        showUpButton(level: level)
        remember(leaving.target)
    }

    /// Shows the up button inside a card, with the chrome of the shown canvas.
    private func showUpButton(level: Int) {
        container.showUpButton(level > 0 ? { [weak self] in self?.leave() } : nil)
    }

    /// Shows the canvas of `target` with its content at `camera`, notes the path, and shows the
    /// up button inside a card (architecture.md 6.4).
    ///
    /// - Throws: `RenderingError` if the renderer does not start.
    func show(_ target: NavigationPath, content: CanvasContent, camera: Camera?) throws {
        guard let canvas = try makeCanvas(target, content: content, camera: camera) else { return }
        container.show(canvas)
        showUpButton(level: target.level)
        remember(target)
    }

    /// Returns the preview source of a new canvas screen, or `nil` without a preview store. It
    /// reads the size of the screen at each render, so a rotation counts (D-98).
    private func previewFiles(repository: any LibraryRepository) -> PreviewFiles? {
        let container = container
        return previewStore.map { store in
            PreviewFiles(
                store: store,
                repository: repository,
                maker: previewMaker,
                viewSize: { @MainActor [weak container] in
                    let bounds = container?.view.bounds ?? .zero
                    return Size(width: bounds.width, height: bounds.height)
                }
            )
        }
    }

    /// Makes the canvas screen of `target` with its content at `camera`. The screen on the
    /// screen keeps its session first, because the new one reads the sessions (F-02).
    ///
    /// - Throws: `RenderingError` if the renderer does not start.
    /// - Returns: The screen, or `nil` before the launch opened the library.
    func makeCanvas(
        _ target: NavigationPath,
        content: CanvasContent,
        camera: Camera?,
        parentCard: Card? = nil
    ) throws -> CanvasViewController? {
        guard let repository, let clock else { return nil }
        precondition(content.canvasID == target.currentCanvas, "The content of the path")
        let canvasID = target.currentCanvas
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(
                configuration: CanvasComposition.rendererConfiguration(defaults),
                previews: previewFiles(repository: repository)
            ),
            clock: clock,
            content: content
        )
        dependencies.camera = camera
        dependencies.repository = repository
        dependencies.sessions = sessions
        dependencies.workspace = target.workspace
        dependencies.transientStrokes = fillStrokes(
            canvasID: canvasID,
            saved: content.strokes.count
        )
        dependencies.onCameraRest = { [weak self] camera in self?.save(camera, for: canvasID) }
        dependencies.onMessage = { [weak self] text in self?.container.showMessage(text) }
        dependencies.level = target.level
        dependencies.isUITest = defaults.string(forKey: AppFiles.uiTestKey) != nil
        dependencies.onOpenCard = { [weak self] card in self?.openChild(card) }
        dependencies.parentCard = parentCard
        dependencies.workspaceTitle = { [weak self] in
            self?.selector?.workspaces.first { $0.id == target.workspace }?.title
        }
        dependencies.onPinchLeave = { [weak self] in self?.leaveByPinch() }
        container.canvas?.endSession()
        let canvas = CanvasViewController(dependencies: dependencies)
        canvas.isEditingEnabled = canEdit
        return canvas
    }

    /// Notes the path of the shown canvas and writes it to the device state (D-53).
    private func remember(_ target: NavigationPath) {
        path = target
        paths[target.workspace] = target
        let deviceStore = deviceStore
        let logger = logger
        Task {
            do {
                try await deviceStore?.save(
                    lastWorkspace: target.workspace,
                    navigationPath: target.cards
                )
            } catch {
                logger.error("The navigation path was not saved: \(error)")
            }
        }
    }
}
