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
            eraserSize: .standard,
            isPreviewOn: true,
            location: Self.location,
            isBlocked: false
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

    @Test(
        "The eraser shows an outline circle with the radius of its size (D-133, D-201)",
        arguments: EraserSize.allCases
    )
    func eraserRing(size: EraserSize) {
        let mark = HoverDot.mark(
            tool: .eraser,
            eraserSize: size,
            isPreviewOn: true,
            location: Self.location,
            isBlocked: false
        )
        #expect(mark == HoverDot(center: Self.location, radius: size.viewPoints, isRing: true))
        #expect(mark?.isRing == true)
    }

    @Test("No mark shows while Show Hover Preview is off", arguments: Tool.allCases)
    func previewOff(tool: Tool) {
        let mark = HoverDot.mark(
            tool: tool,
            eraserSize: .standard,
            isPreviewOn: false,
            location: Self.location,
            isBlocked: false
        )
        #expect(mark == nil)
    }

    @Test(
        "No mark shows while the pencil touches the screen or a card flight runs",
        arguments: Tool.allCases
    )
    func blocked(tool: Tool) {
        let mark = HoverDot.mark(
            tool: tool,
            eraserSize: .standard,
            isPreviewOn: true,
            location: Self.location,
            isBlocked: true
        )
        #expect(mark == nil)
    }

    @Test(
        "A mark shows only with the preview on and no block",
        arguments: [false, true],
        [false, true]
    )
    func gates(isPreviewOn: Bool, isBlocked: Bool) {
        let mark = HoverDot.mark(
            tool: .pen,
            eraserSize: .standard,
            isPreviewOn: isPreviewOn,
            location: Self.location,
            isBlocked: isBlocked
        )
        #expect((mark != nil) == (isPreviewOn && !isBlocked))
    }
}
