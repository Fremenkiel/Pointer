import DesignSystem
import Observation

/// The state and the actions of the current-tool button and the tool palette (TOOL-07, D-63,
/// D-64).
@MainActor
@Observable
final class ToolControls {
    /// The tool that the button shows: the one that the user picked last.
    var selected = Tool.pen
    /// The pen width that the palette marks (TOOL-09, D-199).
    var penWidth = PenWidth.standard
    /// Picks a tool and closes the palette.
    @ObservationIgnored var select: (Tool) -> Void = { _ in }
    /// Picks a pen width and closes the palette.
    @ObservationIgnored var selectWidth: (PenWidth) -> Void = { _ in }
    /// Opens the palette under the button.
    @ObservationIgnored var openPalette: () -> Void = {}
    /// Shows a new card at the left edge of the screen (CARD-01, D-117).
    @ObservationIgnored var newCard: () -> Void = {}
}

extension Tool {
    /// The icon of the tool.
    var icon: String {
        switch self {
        case .pen: DesignSystem.Icon.pen
        case .eraser: DesignSystem.Icon.eraser
        case .text: DesignSystem.Icon.text
        }
    }

    /// The name of the tool for VoiceOver.
    var label: String {
        switch self {
        case .pen: CanvasStrings.pen
        case .eraser: CanvasStrings.eraser
        case .text: CanvasStrings.text
        }
    }
}

extension PenWidth {
    /// The name of the width for VoiceOver.
    var label: String {
        switch self {
        case .thin: CanvasStrings.thinPen
        case .standard: CanvasStrings.standardPen
        case .thick: CanvasStrings.thickPen
        }
    }
}
