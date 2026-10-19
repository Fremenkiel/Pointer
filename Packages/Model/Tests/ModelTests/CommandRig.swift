import Geometry

@testable import Model

/// Makes strokes and holds the clock of the command tests (TEST-04).
struct CommandRig {
    var factory = Fixtures.factory()
    var content = CanvasContent(canvasID: Fixtures.canvas)

    /// The points of every test stroke, shared, as in the app (data-model.md 7.4).
    static let points = InkPoints([
        InkPoint(x: 0, y: 0, force: 1, time: 0), InkPoint(x: 10, y: 0, force: 1, time: 0.1),
    ])

    /// Makes a stroke with a new ID at `x`.
    mutating func stroke(x: Double = 0) -> Stroke {
        Stroke(
            id: factory.identifiers.make(StrokeID.self),
            canvasID: Fixtures.canvas,
            created: factory.clock.now(),
            origin: Point(x: x, y: 0),
            width: 2,
            points: Self.points
        )
    }

    /// Adds strokes to the content without a command, as a load from the library does.
    mutating func load(_ count: Int) throws -> [Stroke] {
        let strokes = (0..<count).map { index in stroke(x: Double(index)) }
        for stroke in strokes {
            try content.add(stroke)
        }
        return strokes
    }

    mutating func apply(_ command: any CanvasCommand) throws(CommandError) -> [LibraryChange] {
        try command.apply(to: &content, clock: &factory.clock)
    }

    mutating func revert(_ command: any CanvasCommand) throws(CommandError) -> [LibraryChange] {
        try command.revert(on: &content, clock: &factory.clock)
    }
}

extension LibraryChange {
    /// The erase record of the change, or `nil` for another row.
    var eraseRecord: EraseRecord? {
        guard case .erase(let record) = self else { return nil }
        return record
    }

    /// The stroke of the change, or `nil` for another row.
    var stroke: Stroke? {
        guard case .stroke(let stroke) = self else { return nil }
        return stroke
    }
}
