import Testing

@testable import CanvasFeature

@Suite("Tool state")
struct ToolStateTests {
    @Test("A tool picked while the pencil is up is active at once")
    func selectWhileUp() {
        var state = ToolState()
        state.select(.eraser)
        #expect(state.active == .eraser)
        #expect(!state.isDrawingEnabled)
        #expect(state.isErasingEnabled)
    }

    @Test("A tool picked during a pencil touch takes effect at the next pencil down (D-70)")
    func selectDuringTouch() {
        var state = ToolState()
        #expect(state.pencilDown() == .pen)
        state.select(.eraser)
        #expect(state.active == .pen)
        #expect(state.selected == .eraser)
        #expect(state.isDrawingEnabled)
        state.pencilUp()
        #expect(state.active == .eraser)
        #expect(state.pencilDown() == .eraser)
    }

    @Test(
        "While the library cannot save, no tool works",
        arguments: Tool.allCases
    )
    func editingFlag(tool: Tool) {
        var state = ToolState()
        state.select(tool)
        state.isEditingEnabled = false
        #expect(!state.isDrawingEnabled)
        #expect(!state.isErasingEnabled)
        #expect(state.selected == tool)
        state.isEditingEnabled = true
        #expect(state.isDrawingEnabled == (tool == .pen))
        #expect(state.isErasingEnabled == (tool == .eraser))
    }

    @Test("The text tool turns off the pen and the eraser, and the editing flag stops it")
    func textTool() {
        var state = ToolState()
        state.select(.text)
        #expect(state.selected == .text)
        #expect(!state.isDrawingEnabled)
        #expect(!state.isErasingEnabled)
        state.isEditingEnabled = false
        #expect(!state.isDrawingEnabled && !state.isErasingEnabled)
    }
}
