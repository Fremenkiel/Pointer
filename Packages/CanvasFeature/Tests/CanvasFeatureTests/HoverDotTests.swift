import DesignSystem
import Testing
import UIKit

@testable import CanvasFeature

@Suite("Hover dot")
struct HoverDotTests {
    private static let location = CGPoint(x: 120.5, y: 80.25)

    @Test(
        "The pen and the text tool show a small filled dot at the tip",
        arguments: [Tool.pen, .text]
    )
    func dot(tool: Tool) {
        let mark = HoverDot.mark(
            tool: tool,
            isPreviewOn: true,
            location: Self.location,
            isPencilDown: false,
            isInFlight: false
        )
        #expect(
            mark
                == HoverDot(
                    center: Self.location,
                    radius: DesignSystem.Size.hoverDotRadius,
                    isRing: false
                )
        )
    }

    @Test("The eraser shows an outline circle with the eraser radius (D-133)")
    func eraserRing() {
        let mark = HoverDot.mark(
            tool: .eraser,
            isPreviewOn: true,
            location: Self.location,
            isPencilDown: false,
            isInFlight: false
        )
        #expect(mark == HoverDot(center: Self.location, radius: 8, isRing: true))
        #expect(mark?.radius == CGFloat(EraserTool.radius))
    }

    @Test("No mark shows while Show Hover Preview is off", arguments: Tool.allCases)
    func previewOff(tool: Tool) {
        let mark = HoverDot.mark(
            tool: tool,
            isPreviewOn: false,
            location: Self.location,
            isPencilDown: false,
            isInFlight: false
        )
        #expect(mark == nil)
    }

    @Test("No mark shows while the pencil touches the screen", arguments: Tool.allCases)
    func pencilDown(tool: Tool) {
        let mark = HoverDot.mark(
            tool: tool,
            isPreviewOn: true,
            location: Self.location,
            isPencilDown: true,
            isInFlight: false
        )
        #expect(mark == nil)
    }

    @Test("No mark shows during a card flight", arguments: Tool.allCases)
    func flight(tool: Tool) {
        let mark = HoverDot.mark(
            tool: tool,
            isPreviewOn: true,
            location: Self.location,
            isPencilDown: false,
            isInFlight: true
        )
        #expect(mark == nil)
    }

    @Test(
        "A mark shows only with the preview on, the pencil up, and no flight",
        arguments: [false, true],
        [false, true]
    )
    func gates(isPencilDown: Bool, isInFlight: Bool) {
        for isPreviewOn in [false, true] {
            let mark = HoverDot.mark(
                tool: .pen,
                isPreviewOn: isPreviewOn,
                location: Self.location,
                isPencilDown: isPencilDown,
                isInFlight: isInFlight
            )
            #expect((mark != nil) == (isPreviewOn && !isPencilDown && !isInFlight))
        }
    }
}
