import Foundation
import Geometry
import Model
import Testing

@testable import Persistence

/// A load refuses an item past the bound of grid cells as a damaged row (task 1.5 of
/// the M9 plan, D-158).
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

    @Test("A card whose title reaches past the grid bound is one skipped row (D-170)")
    func cardTitlePastBound() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.card(try Values.card(3))])
        try await repository.saveNow()
        // The frame touches 4,096 cells, and the renderer adds the title and a margin.
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute("UPDATE card SET x = 1, y = 1, width = 32760, height = 32760")
        let content = try await repository.content(of: Values.canvas)
        try #require(content.cards.isEmpty)
        var faults = harness.faults.makeAsyncIterator()
        #expect(await faults.next() == .rowsSkipped(table: "card", count: 1))
        await repository.close()
    }

    @Test(
        "A stroke inside the canvas bound loads, and one past it is skipped (D-170)",
        arguments: [(Limits.maxCanvasCoordinate - 20, true), (Limits.maxCanvasCoordinate, false)]
    )
    func strokeAtCanvasBound(x: Double, loads: Bool) async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.stroke(Self.stroke(4, offset: 10))])
        try await repository.saveNow()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        let update = try writer.prepare("UPDATE stroke SET origin_x = ?")
        try update.bind(x, at: 1)
        try LibraryStatements.run(update)
        let content = try await repository.content(of: Values.canvas)
        #expect((content.strokes.count == 1) == loads)
        await repository.close()
    }

    @Test("A text box past the canvas bound is one skipped row (D-170)")
    func textBoxPastCanvasBound() async throws {
        let harness = try RepositoryHarness()
        let repository = try await harness.open()
        try await repository.send([.textBox(try Values.textBox(5))])
        try await repository.saveNow()
        let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
        try writer.execute("UPDATE text_box SET y = -1e308")
        let content = try await repository.content(of: Values.canvas)
        try #require(content.textBoxes.isEmpty)
        var faults = harness.faults.makeAsyncIterator()
        #expect(await faults.next() == .rowsSkipped(table: "text_box", count: 1))
        await repository.close()
    }

    /// The largest value from `start` on at which `fits` holds, by steps of one `Double`.
    private static func lastFitting(from start: Double, _ fits: (Double) -> Bool) -> Double {
        var value = start
        // The rounding of the start is a few steps at most (FLOW-03).
        var steps = 0
        while !fits(value), steps < 64 {
            value = value.nextDown
            steps += 1
        }
        while fits(value.nextUp), steps < 128 {
            value = value.nextUp
            steps += 1
        }
        return value
    }

    @Test("A stroke exactly at the canvas bound loads, and one step past it is skipped (TEST-06)")
    func strokeExactlyAtBound() async throws {
        let limit = Limits.maxCanvasCoordinate
        let stroke = Self.stroke(4, offset: 10)
        let extent = stroke.bounds.maxX - stroke.origin.x
        let last = Self.lastFitting(from: limit - extent) { x in
            Stroke(
                id: stroke.id,
                canvasID: stroke.canvasID,
                created: stroke.created,
                origin: Point(x: x, y: 10),
                width: stroke.width,
                points: stroke.points
            ).bounds.maxX <= limit
        }
        for (x, loads) in [(last, true), (last.nextUp, false)] {
            let harness = try RepositoryHarness()
            let repository = try await harness.open()
            try await repository.send([.stroke(stroke)])
            try await repository.saveNow()
            let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
            let update = try writer.prepare("UPDATE stroke SET origin_x = ?")
            try update.bind(x, at: 1)
            try LibraryStatements.run(update)
            let content = try await repository.content(of: Values.canvas)
            #expect((content.strokes.count == 1) == loads, "Origin \(x)")
            await repository.close()
        }
    }

    @Test("A card whose title reach ends exactly at the canvas bound loads (TEST-06, D-170)")
    func cardTitleExactlyAtBound() async throws {
        let limit = Limits.maxCanvasCoordinate
        let card = try Values.card(3)
        let reach = card.frame.size.width + Limits.cardTitleReach
        let last = Self.lastFitting(from: limit - reach) { $0 + reach <= limit }
        for (x, loads) in [(last, true), (last.nextUp, false)] {
            let harness = try RepositoryHarness()
            let repository = try await harness.open()
            try await repository.send([.card(card)])
            try await repository.saveNow()
            let writer = try SQLiteConnection(path: harness.path, mode: .readWrite)
            let update = try writer.prepare("UPDATE card SET x = ?")
            try update.bind(x, at: 1)
            try LibraryStatements.run(update)
            let content = try await repository.content(of: Values.canvas)
            #expect((content.cards.count == 1) == loads, "Frame origin \(x)")
            await repository.close()
        }
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
