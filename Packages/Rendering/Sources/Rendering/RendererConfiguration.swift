/// The start values of the renderer. Tune them on a device (D-28).
public struct RendererConfiguration: Sendable {
    /// The largest size of the point arena. 192 MB holds 12 million control points.
    public var arenaByteBudget: Int
    /// The slabs of 128 KB that the point arena holds at the start. The arena makes whole
    /// buffers of `PointArena.maxSlabsPerBuffer` slabs, so the default of 64 slabs makes one
    /// buffer of 16 MB, not 8 MB (review M9 section 3.3, item 3).
    public var initialArenaSlabs: Int
    /// The draw instances that one frame can spend on a committed texture build. This is the
    /// fixed GPU time per frame of D-28. With the rebuild policy of phase 2, most frames build
    /// nothing, and a chunk of 250,000 instances took up to 9.4 ms of GPU time and made late
    /// frames. 125,000 gave none (frame-loop test, 2026-10-17).
    public var instanceBudgetPerFrame: Int
    /// The draw-list entries per frame.
    public var drawListCapacity: Int
    /// The render-thread time in seconds that one frame can spend on a build. The device test of
    /// 2026-10-17 showed late frames at 120 Hz without this limit.
    public var buildTimeBudget: Double
    /// The byte budget of the glyph atlas: a start value (task 2.2 of docs/m5-plan.md). Tune it
    /// on a device.
    public var glyphAtlasByteBudget: Int
    /// The canvas color in sRGB, each channel from 0 to 1. The composite mixes it with white by
    /// the coverage (CAN-01, D-106). The app passes `DesignSystem.Color.canvasBackgroundSRGB`.
    /// The default is black, so that the coverage tests keep their reference images.
    ///
    /// - Precondition: Each channel is from 0 to 1.
    public var background: SIMD3<Float> = .zero {
        didSet {
            precondition(
                background.min() >= 0 && background.max() <= 1,
                "The background is in sRGB from 0 to 1, got \(background)"
            )
        }
    }
    /// The coverage of a card border, below 1, so that the border shows gray (D-96). The app
    /// passes `DesignSystem.Color.cardBorder`.
    ///
    /// - Precondition: The value is above 0 and below 1.
    public var cardBorderCoverage: Float = defaultCardBorderCoverage {
        didSet {
            precondition(
                cardBorderCoverage > 0 && cardBorderCoverage < 1,
                "A card border has a coverage below 1, got \(cardBorderCoverage)"
            )
        }
    }
    /// The coverage of the body of a card, a light gray on the canvas color (D-116). The app
    /// passes `DesignSystem.Color.cardFill`.
    ///
    /// - Precondition: The value is from 0 to the border coverage.
    public var cardFillCoverage: Float = defaultCardFillCoverage {
        didSet {
            precondition(
                cardFillCoverage >= 0 && cardFillCoverage < 1,
                "A card body has a coverage below 1, got \(cardFillCoverage)"
            )
        }
    }
    /// The coverage of the body of a card without a value of the app: the value of
    /// `DesignSystem.Color.cardFill`.
    public static let defaultCardFillCoverage: Float = 0.065
    /// The coverage of a card border without a value of the app: the value of
    /// `DesignSystem.Color.cardBorder`.
    public static let defaultCardBorderCoverage: Float = 0.5
    /// The width of a card border in view points (architecture.md 5.5).
    static let cardBorderWidth = 1.0
    /// The corner radius of a card in canvas points. The border of a small card takes at most
    /// half its shorter side.
    static let cardCornerRadius = 12.0
    /// The byte budget of the preview atlas: one `.r8Unorm` texture, 2,048 pixels wide (D-97).
    /// 8 MB hold 32 previews of 512, 128 of 256, or 512 of 128 pixels.
    ///
    /// - Precondition: A multiple of 1 MB, so that the blocks of 512 pixels fill whole rows.
    public var previewAtlasByteBudget = 8 << 20
    /// The byte budget of the point arena of one pass of an offscreen preview (D-157). A preview
    /// whose strokes need more draws them in more passes. 32 MB hold about 1.8 million control
    /// points beside the 33 slabs that the size classes can leave partly empty. A preview of a
    /// D-56 child took a peak memory growth of 148 MB with one arena for all of its points.
    ///
    /// - Precondition: At least `PreviewPasses.minimumByteBudget`, so that each stroke fits.
    public var previewArenaByteBudget = 32 << 20
    /// The preview requests that wait for the loader at most (m6-plan.md section 4, rule 5).
    public var previewRequestLimit = 16
    /// The glyph quads per frame. A text box holds at most `Limits.maxTextLength` glyphs, so a
    /// frame holds several boxes.
    public var glyphCapacity: Int

    /// Makes a configuration.
    public init(
        arenaByteBudget: Int = 192 << 20,
        initialArenaSlabs: Int = 64,
        instanceBudgetPerFrame: Int = 125_000,
        drawListCapacity: Int = 32_768,
        buildTimeBudget: Double = 0.002,
        glyphAtlasByteBudget: Int = 16 << 20,
        glyphCapacity: Int = 65_536
    ) {
        self.arenaByteBudget = arenaByteBudget
        self.initialArenaSlabs = initialArenaSlabs
        self.instanceBudgetPerFrame = instanceBudgetPerFrame
        self.drawListCapacity = drawListCapacity
        self.buildTimeBudget = buildTimeBudget
        self.glyphAtlasByteBudget = glyphAtlasByteBudget
        self.glyphCapacity = glyphCapacity
    }
}
