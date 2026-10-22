import Testing
import UIKit

@testable import CanvasFeature

@Suite("Double tap mapping")
struct ToolSwitchTests {
    /// The values of `UIPencilPreferredAction` in the SDK that do not switch the tool (D-130).
    private static let ignoredActions: [UIPencilPreferredAction] = [
        .ignore, .showColorPalette, .showInkAttributes, .showContextualPalette, .runSystemShortcut,
    ]

    /// Raw values after the last value of the SDK, as a later SDK can add (D-130).
    private static let futureRawValues = [7, 8, 99]

    @Test(
        "Switch to eraser and Switch to previous tool switch between pen and eraser",
        arguments: [UIPencilPreferredAction.switchEraser, .switchPrevious]
    )
    func switchingActions(action: UIPencilPreferredAction) {
        #expect(ToolSwitch.tool(after: .pen, action: action) == .eraser)
        #expect(ToolSwitch.tool(after: .eraser, action: action) == .pen)
    }

    @Test(
        "Switch to eraser and Switch to previous tool take the text tool to the pen",
        arguments: [UIPencilPreferredAction.switchEraser, .switchPrevious]
    )
    func textGoesToPen(action: UIPencilPreferredAction) {
        #expect(ToolSwitch.tool(after: .text, action: action) == .pen)
    }

    @Test(
        "Every other setting does nothing with each tool",
        arguments: ignoredActions,
        Tool.allCases
    )
    func ignoredAction(action: UIPencilPreferredAction, tool: Tool) {
        #expect(ToolSwitch.tool(after: tool, action: action) == nil)
    }

    @Test(
        "A setting of a later SDK does nothing with each tool",
        arguments: futureRawValues,
        Tool.allCases
    )
    func futureAction(rawValue: Int, tool: Tool) throws {
        let action = try #require(UIPencilPreferredAction(rawValue: rawValue))
        #expect(ToolSwitch.tool(after: tool, action: action) == nil)
    }

    @Test("The tests cover each value of the SDK")
    func coverage() {
        let switching = [UIPencilPreferredAction.switchEraser, .switchPrevious]
        let covered = Set((switching + Self.ignoredActions).map(\.rawValue))
        #expect(covered == Set(0...6))
        #expect(Self.futureRawValues.allSatisfy { !covered.contains($0) })
    }
}
