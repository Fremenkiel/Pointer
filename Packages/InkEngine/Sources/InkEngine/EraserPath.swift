import Geometry
import Model

/// The path of one eraser gesture in canvas space (architecture.md 4.4).
///
/// The eraser covers a circle of `radius` at each sample and the band between neighbor samples,
/// so a fast pencil leaves no gap between two circles. A grid of the bands finds the bands near a
/// stroke without a loop over the whole path.
public struct EraserPath: Sendable {
    /// The most samples of one gesture: 68 s at 240 Hz, the same bound as a pen stroke.
    public static let maxSamples = Limits.maxPointsPerStroke
    /// The cell size of the band grid, in eraser radii. A band then touches few cells.
    static let cellSizeInRadii = 8.0

    /// The samples of the pencil, in canvas space.
    public let samples: [Point]
    /// The eraser radius in canvas units.
    public let radius: Double
    /// The bounds of the band from sample `i` to sample `i + 1`, plus the radius. A path of one
    /// sample has one band of zero length.
    let bandBounds: [Rect]
    /// The bounds of the whole path, including the radius.
    public let bounds: Rect
    private let grid: SpatialGrid<Int>

    /// Makes the path.
    ///
    /// - Precondition: 1 to `maxSamples` finite samples, and a positive finite radius.
    public init(samples: [Point], radius: Double) {
        precondition(radius > 0 && radius.isFinite, "Eraser radius must be positive, got \(radius)")
        precondition(
            (1...Self.maxSamples).contains(samples.count),
            "An eraser path holds 1 to \(Self.maxSamples) samples, got \(samples.count)"
        )
        precondition(samples.allSatisfy(\.isFinite), "An eraser sample is not finite")
        self.samples = samples
        self.radius = radius
        let bandCount = max(samples.count - 1, 1)
        bandBounds = (0..<bandCount).map { index in
            Rect.bounding([samples[index], samples[min(index + 1, samples.count - 1)]])
                .expanded(by: radius)
        }
        bounds = Rect.bounding(samples).expanded(by: radius)
        var grid = SpatialGrid<Int>(cellSize: radius * Self.cellSizeInRadii)
        for (index, bounds) in bandBounds.enumerated() {
            grid.insert(index, bounds: bounds)
        }
        self.grid = grid
        assert(grid.count == bandBounds.count, "Each band is in the grid")
    }

    /// Returns the indices of the bands whose bounds touch a rectangle, in ascending order.
    func bands(touching rect: Rect) -> [Int] {
        var result: [Int] = []
        grid.forEachItem(touching: rect) { index in result.append(index) }
        result.sort()
        assert(result.count <= bandBounds.count, "A query found more bands than exist")
        return result
    }

    /// Returns the distance from a point to the center line of a band.
    ///
    /// - Precondition: `band` is a band index.
    func distance(from point: Point, toBand band: Int) -> Double {
        precondition(bandBounds.indices.contains(band), "Band \(band) out of the eraser path")
        let start = samples[band]
        let end = samples[min(band + 1, samples.count - 1)]
        let direction = end - start
        let lengthSquared = direction.dx * direction.dx + direction.dy * direction.dy
        guard lengthSquared > 0 else { return point.distance(to: start) }
        let offset = point - start
        let along = (offset.dx * direction.dx + offset.dy * direction.dy) / lengthSquared
        let clamped = min(max(along, 0), 1)
        assert((0...1).contains(clamped), "Projection \(clamped) is off the band")
        return point.distance(to: start + direction * clamped)
    }
}
