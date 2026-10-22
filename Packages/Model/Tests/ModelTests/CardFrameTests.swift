import Geometry
import Testing

@testable import Model

@Suite("Frame of a new card")
struct CardFrameTests {
    @Test(
        "A new card is 320 by 224 canvas points, centered on the point (D-118)",
        arguments: [Point(x: 40, y: -70), Point(x: 1_000_000, y: 1_000_000), .zero]
    )
    func size(center: Point) throws {
        let frame = Card.defaultFrame(at: center)
        #expect(frame.size == Size(width: 320, height: 224))
        #expect(abs(frame.center.x - center.x) < 1e-9)
        #expect(abs(frame.center.y - center.y) < 1e-9)
        #expect(throws: Never.self) { try RecordTests.card(frame: frame) }
    }
}
