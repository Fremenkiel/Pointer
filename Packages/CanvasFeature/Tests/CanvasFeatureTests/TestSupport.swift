import Foundation
import Geometry
import Model
import PencilKit
import Rendering
import UIKit

@testable import CanvasFeature

/// A wall clock that returns a fixed time (TEST-04).
struct FixedWallClock: WallClock {
    func nowMillis() -> UInt64 { 1_700_000_000_000 }
}

/// A deterministic random source: SplitMix64.
struct SeededRandom: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

enum Fixtures {
    static let canvas = CanvasID(
        rawValue: UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    static let device = DeviceID(
        rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    @MainActor
    static func clock() -> AppClock {
        AppClock(
            factory: StrokeFactory(
                identifiers: IdentifierFactory(
                    wallClock: FixedWallClock(),
                    random: SeededRandom(state: 5)
                ),
                clock: HybridClock(device: device, wallClock: FixedWallClock())
            )
        )
    }

    /// A stroke as the live canvas makes it: view points, one point size for all points.
    static func pencilKitStroke(_ points: [CGPoint], pointSize: Double) -> PKStroke {
        let controlPoints = points.enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) / 240,
                size: CGSize(width: pointSize, height: pointSize),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.monoline, color: .white),
            path: PKStrokePath(
                controlPoints: controlPoints,
                creationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    /// A wavy stroke across the middle of a 200 by 120 view.
    static func wave(count: Int = 40) -> [CGPoint] {
        (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return CGPoint(x: 30 + t * 140, y: 60 + sin(t * .pi * 3) * 25)
        }
    }

    /// Renders a drawing as PencilKit draws it, on black, in the light interface style.
    static func pencilKitImage(
        _ drawing: PKDrawing,
        size: CGSize,
        scale: Double
    ) -> RenderedImage? {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: size), scale: scale)
        }
        guard let cgImage = image.cgImage,
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(rect)
        context.draw(cgImage, in: rect)
        guard let bytes = context.makeImage()?.dataProvider?.data as Data? else { return nil }
        return RenderedImage(width: cgImage.width, height: cgImage.height, pixels: Array(bytes))
    }
}

/// The comparison of two ink images, after the M1 spike (Spikes/README.md).
struct InkComparison {
    /// Pixels where either image has ink.
    let comparedPixels: Int
    /// Pixels that differ by more than 64 of 255.
    let differingPixels: Int
    /// The largest difference.
    let maxDifference: Int
    /// The total ink of the first image divided by the total ink of the second image.
    let inkRatio: Double

    init(_ first: RenderedImage, _ second: RenderedImage) {
        var compared = 0
        var differing = 0
        var largest = 0
        var firstInk = 0
        var secondInk = 0
        for y in 0..<first.height {
            for x in 0..<first.width {
                let a = Int(first.gray(x: x, y: y))
                let b = Int(second.gray(x: x, y: y))
                guard a > 0 || b > 0 else { continue }
                compared += 1
                firstInk += a
                secondInk += b
                largest = max(largest, abs(a - b))
                if abs(a - b) > 64 { differing += 1 }
            }
        }
        comparedPixels = compared
        differingPixels = differing
        maxDifference = largest
        inkRatio = secondInk > 0 ? Double(firstInk) / Double(secondInk) : 0
    }
}
