import Testing

@testable import Geometry

@Suite("Points, vectors, sizes, and rectangles")
struct BasicTypesTests {
    @Test("A point minus a point gives the vector between them")
    func pointDifference() {
        let vector = Point(x: 5, y: 7) - Point(x: 2, y: 3)
        #expect(vector == Vector(dx: 3, dy: 4))
        #expect(vector.length == 5)
        #expect(Point(x: 2, y: 3).distance(to: Point(x: 5, y: 7)) == 5)
    }

    @Test("A point plus and minus a vector moves it")
    func pointMove() {
        let point = Point(x: 1, y: 1)
        #expect(point + Vector(dx: 2, dy: -1) == Point(x: 3, y: 0))
        #expect(point - Vector(dx: 2, dy: -1) == Point(x: -1, y: 2))
    }

    @Test("Vector arithmetic works per component")
    func vectorArithmetic() {
        let vector = Vector(dx: 2, dy: -4)
        #expect(vector + Vector(dx: 1, dy: 1) == Vector(dx: 3, dy: -3))
        #expect(vector - Vector(dx: 1, dy: 1) == Vector(dx: 1, dy: -5))
        #expect(vector * 2 == Vector(dx: 4, dy: -8))
        #expect(vector / 2 == Vector(dx: 1, dy: -2))
    }

    @Test("A point with infinity is not finite")
    func finiteness() {
        #expect(Point(x: 1, y: 2).isFinite)
        #expect(!Point(x: .infinity, y: 2).isFinite)
        #expect(!Point(x: 1, y: .nan).isFinite)
    }

    @Test("A rectangle reports its edges and its center")
    func rectEdges() {
        let rect = Rect(minX: -2, minY: 1, maxX: 4, maxY: 9)
        #expect(rect.minX == -2)
        #expect(rect.maxX == 4)
        #expect(rect.minY == 1)
        #expect(rect.maxY == 9)
        #expect(rect.center == Point(x: 1, y: 5))
        #expect(rect.size.halfDiagonal == Vector(dx: 3, dy: 4))
    }

    @Test("Rectangles that touch at an edge intersect, separate ones do not")
    func rectIntersection() {
        let rect = Rect(minX: 0, minY: 0, maxX: 10, maxY: 10)
        #expect(rect.intersects(Rect(minX: 10, minY: 5, maxX: 20, maxY: 6)))
        #expect(rect.intersects(Rect(minX: 2, minY: 2, maxX: 3, maxY: 3)))
        #expect(!rect.intersects(Rect(minX: 10.5, minY: 0, maxX: 20, maxY: 10)))
        #expect(rect.contains(Point(x: 10, y: 0)))
        #expect(!rect.contains(Point(x: 10.1, y: 0)))
    }

    @Test("An expanded rectangle grows on each side")
    func rectExpand() {
        let rect = Rect(minX: 0, minY: 0, maxX: 10, maxY: 4).expanded(by: 1)
        #expect(rect == Rect(minX: -1, minY: -1, maxX: 11, maxY: 5))
    }

    @Test("The bounding rectangle holds all points")
    func bounding() {
        let rect = Rect.bounding([Point(x: 3, y: -1), Point(x: -2, y: 4), Point(x: 0, y: 0)])
        #expect(rect == Rect(minX: -2, minY: -1, maxX: 3, maxY: 4))
        #expect(Rect.bounding([Point(x: 1, y: 1)]).size == .zero)
    }
}
