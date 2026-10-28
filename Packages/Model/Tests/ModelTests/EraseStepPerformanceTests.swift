import Geometry
import XCTest

@testable import Model

/// The model step of the D-69 erase: one `EraseStrokes` on a content of 20,000 strokes removes
/// 1,000 strokes and adds 2,000 parts, as `EraseUndoPerformanceTests` does on the device
/// (the M6 fix plan task 3.1, the M4 plan section 4.6). Run it in Release:
/// `swift test -c release --filter EraseStepPerformanceTests`.
final class EraseStepPerformanceTests: XCTestCase {
    private static let loaded = 20_000
    private static let removed = 1_000
    /// The rounds of each measure, so that the clock of XCTest, in whole milliseconds, shows the
    /// cost of one round in its third decimal.
    private static let rounds = 10

    /// The content, the command, and the clock of one erase.
    private struct Setup {
        var rig: CommandRig
        let command: EraseStrokes
    }

    private static func setup() throws -> Setup {
        var rig = CommandRig()
        let strokes = try rig.load(loaded)
        let cut = Array(strokes.suffix(removed))
        let parts = (0..<(2 * removed)).map { index in rig.stroke(x: Double(index)) }
        return Setup(rig: rig, command: EraseStrokes(removed: cut, parts: parts))
    }

    /// Applies the erase and reverts it. With `copies`, it keeps a copy of the content before
    /// each of the two steps.
    private static func step(_ setup: inout Setup, copies: inout [CanvasContent]) {
        do {
            _ = try setup.rig.apply(setup.command)
            copies.append(setup.rig.content)
            _ = try setup.rig.revert(setup.command)
        } catch {
            XCTFail("The erase step failed: \(error)")
        }
    }

    private static func step(_ setup: inout Setup) {
        do {
            _ = try setup.rig.apply(setup.command)
            _ = try setup.rig.revert(setup.command)
        } catch {
            XCTFail("The erase step failed: \(error)")
        }
    }

    /// One erase and its undo, with the content as the only reference to its dictionaries.
    func testEraseAndUndoOfOneThousandStrokes() throws {
        var setup = try Self.setup()
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<Self.rounds { Self.step(&setup) }
        }
        XCTAssertEqual(setup.rig.content.strokes.count, Self.loaded)
    }

    /// The same step while a second copy of the content exists, as an undo snapshot would make:
    /// the first change of each dictionary then copies it whole.
    func testEraseAndUndoWithASecondCopyOfTheContent() throws {
        var setup = try Self.setup()
        var copies: [CanvasContent] = []
        copies.reserveCapacity(2 * Self.rounds)
        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<Self.rounds {
                copies.append(setup.rig.content)
                Self.step(&setup, copies: &copies)
            }
            copies.removeAll(keepingCapacity: true)
        }
        XCTAssertEqual(setup.rig.content.strokes.count, Self.loaded)
    }
}
