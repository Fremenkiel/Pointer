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
        guard let path, let parent = container.canvas, opening == nil else { return }
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
        loadTask = Task { await loadChild(of: opening, parent: parent) }
    }

    /// Loads the child of an open above the parent at opacity 0 and waits for its first frame.
    private func loadChild(of opening: CardOpening, parent: CanvasViewController) async {
        guard let repository else { return }
        let target = opening.target
        do {
            onLoadStarted?(target.currentCanvas)
            let content = try await repository.content(of: target.currentCanvas)
            guard !Task.isCancelled,
                let canvas = try makeCanvas(target, content: content, camera: content.openCamera)
            else { return }
            container.showAbove(canvas)
            try await CardOpening.waitForFirstFrame(of: canvas)
            opening.canvas = canvas
            finishOpen()
        } catch {
            logger.error("The canvas of a card did not open: \(error)")
            self.opening = nil
            opening.canvas.map(container.removeAbove)
            parent.cancelCardTransition()
            container.showMessage(AppStrings.canvasFailed)
        }
    }

    /// Fades the child in when the flight and its first frame are both done (D-98). Until then,
    /// the screen holds the last frame of the flight.
    private func finishOpen() {
        guard let opening, opening.isFlightDone, let canvas = opening.canvas else { return }
        self.opening = nil
        let level = opening.target.level
        let showChrome: @MainActor () -> Void = { [weak self] in
            self?.container.showUpButton(level > 0 ? { [weak self] in self?.leave() } : nil)
        }
        container.completeSwap(
            to: canvas,
            duration: CanvasRenderer.crossfadeDuration,
            completion: showChrome
        )
        remember(opening.target)
    }

    /// Leaves the current card for its parent canvas at the camera of CARD-04: the standard
    /// zoom, centered on the card (D-99).
    func leave() {
        guard let path, let card = path.cards.last else { return }
        let parent = path.popping()
        loadTask?.cancel()
        loadTask = Task {
            await navigate(to: parent) { content in
                let center = content.cards[card]?.frame.center ?? .zero
                return Camera(center: center, zoom: Limits.standardZoom)
            }
        }
    }

    /// Loads the canvas of `target` and shows it at the camera that `camera` gives for its
    /// content.
    private func navigate(
        to target: NavigationPath,
        camera: (CanvasContent) -> Camera
    ) async {
        guard let repository else { return }
        do {
            onLoadStarted?(target.currentCanvas)
            let content = try await repository.content(of: target.currentCanvas)
            guard !Task.isCancelled else { return }
            try show(target, content: content, camera: camera(content))
        } catch {
            logger.error("The canvas of a card did not open: \(error)")
            container.showMessage(AppStrings.canvasFailed)
        }
    }

    /// Shows the canvas of `target` with its content at `camera`, notes the path, and shows the
    /// up button inside a card (architecture.md 6.4).
    ///
    /// - Throws: `RenderingError` if the renderer does not start.
    func show(_ target: NavigationPath, content: CanvasContent, camera: Camera?) throws {
        guard let canvas = try makeCanvas(target, content: content, camera: camera) else { return }
        container.show(canvas)
        container.showUpButton(target.level > 0 ? { [weak self] in self?.leave() } : nil)
        remember(target)
    }

    /// Makes the canvas screen of `target` with its content at `camera`. The screen on the
    /// screen keeps its session first, because the new one reads the sessions (F-02).
    ///
    /// - Throws: `RenderingError` if the renderer does not start.
    /// - Returns: The screen, or `nil` before the launch opened the library.
    func makeCanvas(
        _ target: NavigationPath,
        content: CanvasContent,
        camera: Camera?
    ) throws -> CanvasViewController? {
        guard let repository, let clock else { return nil }
        precondition(content.canvasID == target.currentCanvas, "The content of the path")
        let canvasID = target.currentCanvas
        let bounds = container.view.bounds
        let screenSize = Size(width: bounds.width, height: bounds.height)
        var dependencies = CanvasDependencies(
            renderer: try CanvasRenderer(
                configuration: CanvasComposition.rendererConfiguration(defaults),
                previews: previewStore.map { store in
                    PreviewFiles(store: store, repository: repository, viewSize: screenSize)
                }
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
        dependencies.level = target.level
        dependencies.onOpenCard = { [weak self] card in self?.openChild(card) }
        container.canvas?.endSession()
        let canvas = CanvasViewController(dependencies: dependencies)
        canvas.isEditingEnabled = !isReadOnly && !areSavesFailing
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
