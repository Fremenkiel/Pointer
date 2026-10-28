/// One run of a stroke with one level of detail: the control points from `start` to `end`.
struct DetailRun: Equatable {
    /// The index of the first control point of the run in the stroke.
    let start: Int
    /// The index of the last control point of the run in the stroke.
    let end: Int
    /// The step between used control points.
    let stride: Int
    /// The pieces per segment.
    let pieces: Int
    /// The offset from `start` back to the neighbor point before the run: the used point of the
    /// run before that comes before its end, at most `start`. 0 at the start of the stroke.
    var previousOffset = 0
    /// The offset from `end` to the neighbor point after the run: the stride of the run after,
    /// at most the points left. 0 at the end of the stroke.
    ///
    /// With the used neighbor points of the two runs, the curves of two runs meet exactly: the
    /// end of one run and the start of the next are both `(p[e - a] + 4 p[e] + p[e + b]) / 6`,
    /// where `a` is the last step of the run before and `b` the stride of the run after.
    var nextOffset = 0

    /// The control points that the draw uses. The last point of the run is always used.
    var usedPointCount: Int { (end - start + stride - 1) / stride + 1 }

    /// The number of draw instances: one per piece.
    var instanceCount: Int { (usedPointCount - 1) * pieces }
}
