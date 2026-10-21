import Geometry
import Testing

@testable import Model

@Suite("Frame of a new card")
struct CardFrameTests {
    /// The 11-inch iPad in landscape and in portrait, in view points.
    private static let wide = Size(width: 1194, height: 834)
    private static let tall = Size(width: 834, height: 1194)

    @Test(
        "A new card is a quarter of the view width at the zoom, with the aspect of the view",
        arguments: [(0.25, wide), (1.0, wide), (0.25, tall), (1.0, tall)]
    )
    func size(zoom: Double, view: Size) throws {
        let press = Point(x: 40, y: -70)
        let camera = Camera(center: .zero, zoom: zoom)
        let frame = Card.defaultFrame(at: press, camera: camera, viewSize: view)
        let width = view.width / 4 / zoom
        #expect(abs(frame.size.width - width) < 1e-9)
        #expect(abs(frame.size.height - width * view.height / view.width) < 1e-9)
        #expect(abs(frame.center.x - press.x) < 1e-9)
        #expect(abs(frame.center.y - press.y) < 1e-9)
        #expect(throws: Never.self) { try RecordTests.card(frame: frame) }
    }

    @Test("At zoom 8 the minimum of 64 by 48 sets the size", arguments: [wide, tall])
    func minimum(view: Size) throws {
        let camera = Camera(center: .zero, zoom: Limits.maxZoom)
        let frame = Card.defaultFrame(at: Point(x: 5, y: 5), camera: camera, viewSize: view)
        #expect(frame.size == Size(width: Limits.minCardWidth, height: Limits.minCardHeight))
        #expect(frame.center == Point(x: 5, y: 5))
        #expect(throws: Never.self) { try RecordTests.card(frame: frame) }
    }

    @Test("A wide view at a high zoom keeps the width and raises the height to the minimum")
    func oneSideAtMinimum() {
        let view = Size(width: 2400, height: 300)
        let frame = Card.defaultFrame(
            at: .zero,
            camera: Camera(center: .zero, zoom: 4),
            viewSize: view
        )
        #expect(frame.size == Size(width: 150, height: Limits.minCardHeight))
    }

    @Test("A press far from the origin centers the card on the press point")
    func farPress() throws {
        let press = Point(x: 1_000_000, y: 1_000_000)
        let camera = Camera(center: press, zoom: 1)
        let frame = Card.defaultFrame(at: press, camera: camera, viewSize: Self.wide)
        #expect(frame.center == press)
        #expect(frame.size == Size(width: 298.5, height: 208.5))
        #expect(throws: Never.self) { try RecordTests.card(frame: frame) }
    }
}
