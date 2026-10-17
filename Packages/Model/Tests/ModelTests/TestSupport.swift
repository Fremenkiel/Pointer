import Foundation
import Geometry

@testable import Model

/// A wall clock that returns a fixed time (TEST-04).
struct FixedWallClock: WallClock {
    let millis: UInt64

    func nowMillis() -> UInt64 { millis }
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
    static let device = DeviceID(
        rawValue: UUID(uuid: (1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )
    static let canvas = CanvasID(
        rawValue: UUID(uuid: (2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    )

    static func factory(millis: UInt64 = 1_700_000_000_000) -> StrokeFactory {
        let clock = FixedWallClock(millis: millis)
        return StrokeFactory(
            identifiers: IdentifierFactory(wallClock: clock, random: SeededRandom(state: 7)),
            clock: HybridClock(device: device, wallClock: clock)
        )
    }

    static func samples(count: Int) -> [ControlPointSample] {
        (0..<count).map { index in
            ControlPointSample(
                location: Point(x: Double(index), y: Double(index % 7)),
                force: 0.5,
                timeOffset: Double(index) / 240
            )
        }
    }

    static func stroke(points: [InkPoint], width: Float = 2) -> Stroke {
        var factory = factory()
        return Stroke(
            id: factory.identifiers.make(StrokeID.self),
            canvasID: canvas,
            created: factory.clock.now(),
            origin: Point(x: 100, y: 200),
            width: width,
            points: InkPoints(points)
        )
    }
}
