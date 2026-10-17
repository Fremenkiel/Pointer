import Foundation
import PencilKit

/// Identifies one `PKStroke` in the live drawing. `PKStroke` has no ID, so the key combines the
/// random seed, the creation date, and the point count.
struct StrokeKey: Hashable {
    let randomSeed: UInt32
    let creationDate: Date
    let pointCount: Int

    /// Makes the key of a stroke.
    init(_ stroke: PKStroke) {
        randomSeed = stroke.randomSeed
        creationDate = stroke.path.creationDate
        pointCount = stroke.path.count
    }
}
