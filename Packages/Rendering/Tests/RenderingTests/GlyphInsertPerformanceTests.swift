import Metal
import QuartzCore
import XCTest

@testable import Rendering

/// The time of 4,000 new glyphs in the atlas, with their rasters and uploads (review M9 section
/// 3.3, item 6, m10-plan.md task 3.5). Before the fix, each insert copied the key list of its
/// page, which cost 807 µs of the 4,000 inserts on the Mac.
@MainActor
final class GlyphInsertPerformanceTests: XCTestCase {
    /// The glyphs of SF Mono per scale. 1,000 glyphs at 4 scales make 4,000 inserts.
    private static let glyphsPerScale = 1_000
    private static let exponents = 0..<4

    func testFourThousandInserts() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let font = TextLayout.baseFont
        var times: [Double] = []
        var inserted = 0
        for _ in 0..<7 {
            let atlas = GlyphAtlas(device: device, byteBudget: 64 << 20)
            inserted = 0
            let start = CACurrentMediaTime()
            for exponent in Self.exponents {
                for glyph in 1...Self.glyphsPerScale {
                    let place = atlas.placement(
                        of: CGGlyph(glyph),
                        font: font,
                        exponent: exponent,
                        frame: 1
                    )
                    if let place, place.page >= 0 { inserted += 1 }
                }
            }
            times.append((CACurrentMediaTime() - start) * 1_000)
        }
        let median = times.sorted()[times.count / 2]
        let line = String(format: "%d glyph inserts: median %.3f ms", inserted, median)
        XCTContext.runActivity(named: line) { _ in }
        PerformanceRecord.attach(["inserts.median.ms": median])
        XCTAssertGreaterThan(inserted, 3_000, "Most glyphs of SF Mono have a bitmap")
    }
}
