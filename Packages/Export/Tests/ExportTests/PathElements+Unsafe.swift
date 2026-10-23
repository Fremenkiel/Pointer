import CoreGraphics

/// Reads the elements of a `CGPath` for the tests.
enum PathElements {
    /// One element of a path: its kind and its points.
    struct Element: Equatable {
        let kind: CGPathElementType
        let points: [CGPoint]
    }

    /// Returns the elements of a path, in order.
    static func of(_ path: CGPath) -> [Element] {
        var elements: [Element] = []
        path.applyWithBlock { pointer in
            // Core Graphics gives a valid element for the time of the call, and the element holds
            // as many points as its type needs, so the copy reads only valid memory.
            let element = pointer.pointee
            let count: Int
            switch element.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            default: count = 0
            }
            let points = (0..<count).map { element.points[$0] }
            elements.append(Element(kind: element.type, points: points))
        }
        return elements
    }
}
