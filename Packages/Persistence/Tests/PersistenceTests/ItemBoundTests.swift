import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

/// A load refuses an item past the bound of grid cells as a damaged row (task 1.5 of
/// docs/m9-plan.md, D-158).
@Suite("Bounds of the items of a load")
struct ItemBoundTests {
    /// The offset of the last point of a stroke at (10, 10) with a width of 2 whose bounds touch
    /// exactly `Limits.maxGridCellsPerItem` cells of one row: the bounds end at offset + 11.
    static let offsetAtLimit = Float(
        Double(Limits.maxGridCellsPerItem) * Limits.gridCellSize - 12
    )

    @Test("A stroke row 10,000,000 points wide is one skipped row, in milliseconds")
    func wideStroke() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.stroke(Self.stroke(1, offset: 10_000_000))])
        try await repository.saveNow()
        let clock = ContinuousClock()
        let start = clock.now
        let content = try await repository.content(of: Values.canvas)
        #expect(start.duration(to: clock.now) < .seconds(1))
        // Without a skipped row, no fault comes, so the test stops here.
        try #require(content.strokes.isEmpty)
        var faults = harness.faults.makeAsyncIterator()
        #expect(await faults.next() == .rowsSkipped(table: "stroke", count: 1))
        await repository.close()
    }

    @Test(
        "A stroke at the bound loads, and a stroke one cell past it is skipped",
        arguments: [(0, true), (1, false)]
    )
    func strokeAtBound(extra: Float, loads: Bool) async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        let stroke = Self.stroke(2, offset: Self.offsetAtLimit + extra)
        let cells = GridCell.count(covering: stroke.bounds, cellSize: Limits.gridCellSize)
        #expect(cells == Limits.maxGridCellsPerItem + Int(extra))
        try await repository.send([.stroke(stroke)])
        try await repository.saveNow()
        let content = try await repository.content(of: Values.canvas)
        #expect((content.strokes.count == 1) == loads)
        await repository.close()
    }

    @Test("A card row 10,000,000 points wide is one skipped row")
    func wideCard() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.card(try Values.card(3))])
        try await repository.saveNow()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute("UPDATE card SET width = 10000000")
        let content = try await repository.content(of: Values.canvas)
        try #require(content.cards.isEmpty)
        var faults = harness.faults.makeAsyncIterator()
        #expect(await faults.next() == .rowsSkipped(table: "card", count: 1))
        await repository.close()
    }

    /// A stroke at (10, 10) from its origin to `offset` points to the right.
    private static func stroke(_ byte: UInt8, offset: Float) -> Stroke {
        Stroke(
            id: StrokeID(rawValue: UUID(uuid: (9, byte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))),
            canvasID: Values.canvas,
            created: Values.early,
            origin: Point(x: 10, y: 10),
            width: 2,
            points: InkPoints([
                InkPoint(x: 0, y: 0, force: 1, time: 0),
                InkPoint(x: offset, y: 0, force: 1, time: 0.1),
            ])
        )
    }
}
