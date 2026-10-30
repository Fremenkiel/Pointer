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
    /// The undo histories of the app, or `nil` for a canvas whose history ends with it (D-12).
    public var sessions: CanvasSessions?
    /// The pen width of the app, shared by every canvas while it runs (TOOL-09, D-199), or `nil`
    /// for a canvas with settings of its own.
    public var penSettings: PenSettings?
    /// The workspace of the canvas, so that a delete of the workspace removes the session of the
    /// canvas (D-196), or `nil` for a canvas without a workspace.
    public var workspace: WorkspaceID?
    /// Receives the camera when it comes to rest, for the device state (D-53).
    public var onCameraRest: @MainActor (Camera) -> Void = { _ in }
    /// Shows a short message, for example at a limit (architecture.md section 10).
    public var onMessage: @MainActor (String) -> Void = { _ in }
    /// Opens a card after a tap on it (CARD-03, D-115).
    public var onOpenCard: @MainActor (Card) -> Void = { _ in }
    /// Gives the title of the workspace of this canvas for the name of an exported PDF, or `nil`
    /// (D-143).
    public var workspaceTitle: @MainActor () -> String? = { nil }
    /// The card of this canvas in its parent, for the pinch-out exit, or `nil` (CARD-05).
    public var parentCard: Card?
    /// Leaves this canvas for its parent after a pinch-out exit (CARD-05).
    public var onPinchLeave: @MainActor () -> Void = {}
    /// `true` for a UI test. The palm guard then takes the larger radius of the synthesized
    /// touches of XCTest (D-191). The app keeps `false`.
    public var isUITest = false
    /// The level of the canvas in the card tree: 0 for the root canvas (D-95).
    ///
    /// - Precondition: From 0 to `Limits.maxDepth`.
    public var level = 0 {
        didSet {
            precondition((0...Limits.maxDepth).contains(level), "Level \(level) of the canvas")
        }
    }

    /// Makes the dependencies of a canvas without a stored camera, fill content, or storage.
    public init(renderer: CanvasRenderer, clock: AppClock, content: CanvasContent) {
        self.renderer = renderer
        self.clock = clock
        self.content = content
    }

    /// The canvas to show.
    public var canvasID: CanvasID { content.canvasID }
}
