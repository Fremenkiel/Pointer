import Testing

@testable import Geometry

/// The union and the common part of two rectangles (review of 2026-10-28, 3.4.3).
@Suite("Rectangles")
struct RectTests {
    private static let left = Rect(minX: 0, minY: 0, maxX: 10, maxY: 10)

    @Test("The union holds both rectangles, also one inside the other")
    func union() {
        let right = Rect(minX: 5, minY: -5, maxX: 20, maxY: 5)
        #expect(Self.left.union(right) == Rect(minX: 0, minY: -5, maxX: 20, maxY: 10))
        #expect(right.union(Self.left) == Rect(minX: 0, minY: -5, maxX: 20, maxY: 10))
        let inside = Rect(minX: 2, minY: 2, maxX: 3, maxY: 3)
        #expect(Self.left.union(inside) == Self.left)
    }

    @Test(
        "The common part is the overlap, an edge for touching rectangles, and none apart",
        arguments: [
            (
                Rect(minX: 5, minY: 5, maxX: 20, maxY: 20),
                Rect(minX: 5, minY: 5, maxX: 10, maxY: 10)
            ),
            (
                Rect(minX: 10, minY: 0, maxX: 20, maxY: 10),
                Rect(minX: 10, minY: 0, maxX: 10, maxY: 10)
            ),
            (Rect(minX: 11, minY: 0, maxX: 20, maxY: 10), nil),
            (Rect(minX: 0, minY: -10, maxX: 10, maxY: -1), nil),
        ]
    )
    func intersection(other: Rect, expected: Rect?) {
        #expect(Self.left.intersection(other) == expected)
        #expect(other.intersection(Self.left) == expected)
    }
}
