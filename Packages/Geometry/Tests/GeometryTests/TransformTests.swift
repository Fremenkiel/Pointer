import Testing

@testable import Geometry

@Suite("Affine transforms")
struct TransformTests {
    private let skew = Transform(a: 2, b: 0.5, c: -1, d: 3, tx: 10, ty: -4)

    @Test("The identity changes no point")
    func identity() {
        let point = Point(x: 3, y: -7)
        #expect(Transform.identity.apply(to: point) == point)
    }

    @Test("A transform maps a point as CGAffineTransform does")
    func apply() {
        let point = skew.apply(to: Point(x: 1, y: 2))
        #expect(point == Point(x: 2 * 1 - 1 * 2 + 10, y: 0.5 * 1 + 3 * 2 - 4))
    }

    @Test("A transform then its inverse gives the identity")
    func inverse() {
        let roundTrip = skew.then(skew.inverted())
        let point = roundTrip.apply(to: Point(x: 12.5, y: -3))
        #expect(abs(point.x - 12.5) < 1e-12)
        #expect(abs(point.y + 3) < 1e-12)
    }

    @Test("then applies the first transform first")
    func order() {
        let scale = Transform(scale: 2, translation: .zero)
        let move = Transform(scale: 1, translation: Vector(dx: 5, dy: 0))
        #expect(scale.then(move).apply(to: Point(x: 1, y: 1)) == Point(x: 7, y: 2))
        #expect(move.then(scale).apply(to: Point(x: 1, y: 1)) == Point(x: 12, y: 2))
    }

    @Test("The determinant of a scale is the square of the factor")
    func determinant() {
        #expect(Transform(scale: 3, translation: .zero).determinant == 9)
    }
}
