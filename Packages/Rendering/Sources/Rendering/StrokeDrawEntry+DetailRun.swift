extension StrokeDrawEntry {
    /// Makes the entry of one level-of-detail run.
    ///
    /// - Precondition: `bufferOffset` and `firstInstance` are zero or positive.
    init(
        _ run: DetailRun,
        origin: SIMD2<Float>,
        bufferOffset: Int,
        firstInstance: Int,
        radius: Float
    ) {
        precondition(bufferOffset >= 0, "Buffer offset \(bufferOffset) is negative")
        precondition(firstInstance >= 0, "First instance \(firstInstance) is negative")
        self.init(
            origin: origin,
            firstPoint: UInt32(bufferOffset + run.start),
            pointCount: UInt32(run.end - run.start + 1),
            firstSegment: Self.packStart(start: run.start, previousOffset: run.previousOffset),
            detail: Self.packDetail(
                stride: run.stride,
                pieces: run.pieces,
                nextOffset: run.nextOffset
            ),
            firstInstance: UInt32(firstInstance),
            radius: radius
        )
    }
}
