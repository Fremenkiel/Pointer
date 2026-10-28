import Geometry
import Model

/// The SQL and the codec of the `stroke` table (storage.md sections 3.3 and 3.4).
enum StrokeRow {
    /// The number of parameters of the write statement.
    static let parameterCount: Int32 = 12
    /// The number of columns of the read statement.
    static let columnCount: Int32 = 8

    /// Writes a stroke. Strokes never change, so a row with the same ID stays as it is.
    static let insert: StaticString = """
        INSERT INTO stroke (
            id, canvas_id, created, origin_x, origin_y, width, min_x, min_y, max_x, max_y,
            point_count, points)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO NOTHING
        """

    /// Reads the live strokes of one canvas: the strokes without a live erase record (storage.md
    /// section 5, review A-07).
    static let selectLive: StaticString = """
        SELECT s.id, s.canvas_id, s.created, s.origin_x, s.origin_y, s.width, s.point_count,
            s.points
        FROM stroke s LEFT JOIN stroke_erase e ON e.stroke_id = s.id AND e.is_deleted = 0
        WHERE s.canvas_id = ? AND e.stroke_id IS NULL
        """

    /// Counts the live strokes of one canvas, for the report of a load past the limit.
    static let countLive: StaticString = """
        SELECT count(*) FROM stroke s
        LEFT JOIN stroke_erase e ON e.stroke_id = s.id AND e.is_deleted = 0
        WHERE s.canvas_id = ? AND e.stroke_id IS NULL
        """

    /// Binds `stroke` to the parameters of `insert`.
    ///
    /// - Throws: `PersistenceError.sqlite` if a bind fails.
    static func bind(_ stroke: Stroke, to statement: SQLiteStatement) throws(PersistenceError) {
        precondition(statement.parameterCount == parameterCount, "Not a stroke write")
        var binder = try RowBinder(statement)
        try binder.bind(stroke.id)
        try binder.bind(stroke.canvasID)
        try binder.bind(stroke.created)
        try binder.bind(stroke.origin.x)
        try binder.bind(stroke.origin.y)
        try binder.bind(Double(stroke.width))
        try binder.bind(stroke.bounds.minX)
        try binder.bind(stroke.bounds.minY)
        try binder.bind(stroke.bounds.maxX)
        try binder.bind(stroke.bounds.maxY)
        try binder.bind(Int64(stroke.points.count))
        try binder.bind(stroke.points)
        assert(binder.count == statement.parameterCount, "Stroke binds all parameters")
    }

    /// Reads the current row of `selectLive`.
    ///
    /// - Throws: `PersistenceError.corruptRow` if a column does not give a valid stroke, for
    ///   example a point BLOB with a wrong length (storage.md section 9).
    static func read(from statement: SQLiteStatement) throws(PersistenceError) -> Stroke {
        precondition(statement.columnCount == columnCount, "Not a stroke read")
        var reader = RowReader(statement, table: "stroke")
        let id: StrokeID = try reader.identifier()
        let canvasID: CanvasID = try reader.identifier()
        let created = try reader.timestamp()
        let origin = Point(x: try reader.double(), y: try reader.double())
        let storedWidth = try reader.double()
        // Stroke refuses a width that is not positive with a precondition.
        guard let width = Float(exactly: storedWidth), width > 0, width.isFinite else {
            throw reader.corrupt("width \(storedWidth)")
        }
        let storedCount = try reader.int64()
        guard let count = Int(exactly: storedCount) else {
            throw reader.corrupt("point count \(storedCount)")
        }
        let points = try reader.inkPoints(count: count)
        let stroke = Stroke(
            id: id,
            canvasID: canvasID,
            created: created,
            origin: origin,
            width: width,
            points: points
        )
        try reader.checkBounds(stroke.bounds)
        return stroke
    }
}
