import Geometry
import Model
import Rendering

/// The dependencies of the canvas screen. `PointerApp` makes them (ARCH-05).
public struct CanvasDependencies {
    /// The renderer of the canvas.
    public let renderer: CanvasRenderer
    /// The clock of the app, shared with the workspace selector.
    public let clock: AppClock
    /// The content that the library loaded: the live rows of the canvas.
    public let content: CanvasContent
    /// The camera at the start, or `nil` for the standard camera.
    public var camera: Camera?
    /// Strokes that the canvas shows but never saves: the fill content of the performance tests
    /// (D-55).
    public var transientStrokes: [Stroke] = []
    /// The library that saves the new strokes, or `nil` for a canvas without storage.
    public var repository: (any LibraryRepository)?
    /// Receives the camera when it comes to rest, for the device state (D-53).
    public var onCameraRest: @MainActor (Camera) -> Void = { _ in }

    /// Makes the dependencies of a canvas without a stored camera, fill content, or storage.
    public init(renderer: CanvasRenderer, clock: AppClock, content: CanvasContent) {
        self.renderer = renderer
        self.clock = clock
        self.content = content
    }

    /// The canvas to show.
    public var canvasID: CanvasID { content.canvasID }
}
