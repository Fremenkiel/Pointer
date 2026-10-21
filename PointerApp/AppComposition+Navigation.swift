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

    /// Opens the child canvas of a card at the camera of CARD-03: the standard zoom, centered
    /// on the content bounds of the child (D-99).
    func openChild(_ card: Card) {
        guard let path else { return }
        let child: NavigationPath
        do {
            child = try path.pushing(card.id)
        } catch {
            logger.error("A card below level 32 does not open: \(error)")
            return
        }
        loadTask?.cancel()
        loadTask = Task { await navigate(to: child) { $0.openCamera } }
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
        guard let repository, let clock else { return }
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
        // The new screen reads the sessions, so the old one keeps its steps first (F-02).
        container.canvas?.endSession()
        let canvas = CanvasViewController(dependencies: dependencies)
        canvas.isEditingEnabled = !isReadOnly && !areSavesFailing
        container.show(canvas)
        container.showUpButton(target.level > 0 ? { [weak self] in self?.leave() } : nil)
        remember(target)
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
