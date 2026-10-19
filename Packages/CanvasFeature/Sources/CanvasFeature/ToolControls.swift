import DesignSystem
import Observation

/// The state and the actions of the current-tool button and the tool palette (TOOL-07, D-63,
/// D-64).
@MainActor
@Observable
final class ToolControls {
    /// The tool that the button shows: the one that the user picked last.
    var selected = Tool.pen
    /// Picks a tool and closes the palette.
    @ObservationIgnored var select: (Tool) -> Void = { _ in }
    /// Opens the palette under the button.
    @ObservationIgnored var openPalette: () -> Void = {}
}

extension Tool {
    /// The icon of the tool.
    var icon: String {
        switch self {
        case .pen: DesignSystem.Icon.pen
        case .eraser: DesignSystem.Icon.eraser
        }
    }

    /// The name of the tool for VoiceOver.
    var label: String {
        switch self {
        case .pen: CanvasStrings.pen
        case .eraser: CanvasStrings.eraser
        }
    }
}
