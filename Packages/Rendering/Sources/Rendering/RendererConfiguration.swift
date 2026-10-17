/// The start values of the renderer. Tune them on a device (D-28).
public struct RendererConfiguration: Sendable {
    /// The largest size of the point arena. 192 MB holds 12 million control points.
    public var arenaByteBudget: Int
    /// The size of the point arena at the start, in slabs of 256 KB.
    public var initialArenaSlabs: Int
    /// The draw instances that one frame can spend on a committed texture build. This is the
    /// fixed GPU time per frame of D-28.
    public var instanceBudgetPerFrame: Int
    /// The draw-list entries per frame.
    public var drawListCapacity: Int
    /// The main-thread time in seconds that one frame can spend on a build. The device test of
    /// 2026-10-17 showed late frames at 120 Hz without this limit.
    public var buildTimeBudget: Double

    /// Makes a configuration.
    public init(
        arenaByteBudget: Int = 192 << 20,
        initialArenaSlabs: Int = 64,
        instanceBudgetPerFrame: Int = 250_000,
        drawListCapacity: Int = 32_768,
        buildTimeBudget: Double = 0.002
    ) {
        self.arenaByteBudget = arenaByteBudget
        self.initialArenaSlabs = initialArenaSlabs
        self.instanceBudgetPerFrame = instanceBudgetPerFrame
        self.drawListCapacity = drawListCapacity
        self.buildTimeBudget = buildTimeBudget
    }
}
