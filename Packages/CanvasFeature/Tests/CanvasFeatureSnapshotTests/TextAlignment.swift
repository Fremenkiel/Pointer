import Rendering

/// The pass rule of M5 acceptance 2 (D-91): for each line of text, the bounds of the lit pixels
/// of two images differ by at most 1 pixel on each side, and their column and row profiles match
/// best at an offset of at most 1 pixel.
enum TextAlignment {
    /// A pixel with a coverage of 50 % or more is lit (D-91).
    static let litThreshold: UInt8 = 128
    /// The largest offset that the profile search tries, in pixels.
    static let searchRange = 4

    /// The measures of one line band in two images.
    struct LineResult: CustomStringConvertible {
        let line: Int
        /// The largest difference of the four sides of the lit bounds, in pixels.
        let boundsDifference: Int
        /// The offset of the best match of the column profiles, in pixels.
        let columnOffset: Int
        /// The offset of the best match of the row profiles, in pixels.
        let rowOffset: Int

        /// `true` if the line meets the rule of D-91.
        var passes: Bool { boundsDifference <= 1 && abs(columnOffset) <= 1 && abs(rowOffset) <= 1 }

        var description: String {
            let offsets = "columns \(columnOffset) px, rows \(rowOffset) px"
            return "line \(line): bounds \(boundsDifference) px, \(offsets)"
        }
    }

    /// The bounds of the lit pixels of a band.
    struct PixelBounds {
        var minX: Int
        var maxX: Int
        var minY: Int
        var maxY: Int
    }

    /// Compares the line bands of two images of the same size.
    ///
    /// - Parameters:
    ///   - canvas: The image of the canvas.
    ///   - edit: The image of the edit view.
    ///   - bands: The first and the last pixel row of each line.
    /// - Returns: The measures of each line that shows in both images.
    static func compare(
        _ canvas: RenderedImage,
        _ edit: RenderedImage,
        bands: [ClosedRange<Int>]
    ) -> [LineResult] {
        precondition(canvas.width == edit.width && canvas.height == edit.height, "Sizes differ")
        return bands.enumerated().compactMap { index, band in
            guard let first = bounds(canvas, band), let second = bounds(edit, band) else {
                return nil
            }
            let difference =
                [
                    abs(first.minX - second.minX), abs(first.maxX - second.maxX),
                    abs(first.minY - second.minY), abs(first.maxY - second.maxY),
                ].max() ?? 0
            return LineResult(
                line: index,
                boundsDifference: difference,
                columnOffset: bestOffset(columns(canvas, band), columns(edit, band)),
                rowOffset: bestOffset(rows(canvas, band), rows(edit, band))
            )
        }
    }

    /// The bounds of the lit pixels of a band, or `nil` if the band has none.
    static func bounds(_ image: RenderedImage, _ band: ClosedRange<Int>) -> PixelBounds? {
        var result: PixelBounds?
        for y in band where y >= 0 && y < image.height {
            for x in 0..<image.width where image.gray(x: x, y: y) >= litThreshold {
                var next = result ?? PixelBounds(minX: x, maxX: x, minY: y, maxY: y)
                next.minX = min(next.minX, x)
                next.maxX = max(next.maxX, x)
                next.minY = min(next.minY, y)
                next.maxY = max(next.maxY, y)
                result = next
            }
        }
        return result
    }

    private static func columns(_ image: RenderedImage, _ band: ClosedRange<Int>) -> [Int] {
        (0..<image.width).map { x in
            band.filter { $0 >= 0 && $0 < image.height }.reduce(0) {
                $0 + Int(image.gray(x: x, y: $1))
            }
        }
    }

    private static func rows(_ image: RenderedImage, _ band: ClosedRange<Int>) -> [Int] {
        band.filter { $0 >= 0 && $0 < image.height }.map { y in
            (0..<image.width).reduce(0) { $0 + Int(image.gray(x: $1, y: y)) }
        }
    }

    /// The shift of `second` against `first` with the smallest sum of absolute differences.
    private static func bestOffset(_ first: [Int], _ second: [Int]) -> Int {
        precondition(first.count == second.count, "Profiles differ in length")
        var best = (offset: 0, cost: Int.max)
        for offset in -searchRange...searchRange {
            var cost = 0
            for index in first.indices {
                let other = index + offset
                let value = other >= 0 && other < second.count ? second[other] : 0
                cost += abs(first[index] - value)
            }
            if cost < best.cost || (cost == best.cost && abs(offset) < abs(best.offset)) {
                best = (offset, cost)
            }
        }
        return best.offset
    }
}
