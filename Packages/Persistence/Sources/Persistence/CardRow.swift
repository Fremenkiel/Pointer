import Geometry
import Model

/// The SQL and the codec of the `card` table (storage.md section 3.3).
enum CardRow {
    /// The number of parameters of the write statement.
    static let parameterCount: Int32 = 11
    /// The number of columns of the read statement.
    static let columnCount: Int32 = 11

    /// Writes a card. A row with the same ID takes the new values.
    static let upsert: StaticString = """
        INSERT INTO card (
            id, canvas_id, x, y, width, height, title, sort_key, created, modified, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET canvas_id = excluded.canvas_id, x = excluded.x,
            y = excluded.y, width = excluded.width, height = excluded.height,
            title = excluded.title, sort_key = excluded.sort_key, modified = excluded.modified,
            is_deleted = excluded.is_deleted
        """

    /// Reads the live cards of one canvas.
    static let selectLive: StaticString = """
        SELECT id, canvas_id, x, y, width, height, title, sort_key, created, modified, is_deleted
        FROM card WHERE canvas_id = ? AND is_deleted = 0
        """

    /// Counts the live cards of one canvas, for the report of a load past the limit.
    static let countLive: StaticString = """
        SELECT count(*) FROM card WHERE canvas_id = ? AND is_deleted = 0
        """

    /// Reads the IDs and the parents of up to `Limits.maxDepth` live cards, for the check of a
    /// navigation path (D-112). An unused parameter takes NULL, which matches no row.
    static let selectPath: StaticString = """
        SELECT id, canvas_id FROM card WHERE is_deleted = 0 AND id IN (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

    /// Binds `card` to the parameters of `upsert`.
    ///
    /// - Throws: `PersistenceError.sqlite` if a bind fails.
    static func bind(_ card: Card, to statement: SQLiteStatement) throws(PersistenceError) {
        precondition(statement.parameterCount == parameterCount, "Not a card write")
        var binder = try RowBinder(statement)
        try binder.bind(card.id)
        try binder.bind(card.canvasID)
        try binder.bind(card.frame.origin.x)
        try binder.bind(card.frame.origin.y)
        try binder.bind(card.frame.size.width)
        try binder.bind(card.frame.size.height)
        try binder.bind(card.title)
        try binder.bind(card.sortKey.rawValue)
        try binder.bind(card.meta)
        assert(binder.count == statement.parameterCount, "Card binds all parameters")
    }

    /// Reads the current row of `selectLive`.
    ///
    /// - Throws: `PersistenceError.corruptRow` if a column does not give a valid card.
    static func read(from statement: SQLiteStatement) throws(PersistenceError) -> Card {
        precondition(statement.columnCount == columnCount, "Not a card read")
        var reader = RowReader(statement, table: "card")
        let id: CardID = try reader.identifier()
        let canvasID: CanvasID = try reader.identifier()
        let origin = Point(x: try reader.double(), y: try reader.double())
        let width = try reader.double()
        let height = try reader.double()
        // Rect refuses a negative size with a precondition, so a bad file must stop here.
        guard width >= 0, height >= 0 else { throw reader.corrupt("negative card size") }
        let frame = Rect(origin: origin, size: Size(width: width, height: height))
        let title = try reader.optionalString()
        let sortKey = try reader.sortKey()
        let meta = try reader.meta()
        // The renderer holds the card with its title in its grid (D-170).
        try reader.checkBounds(frame.expanded(by: Limits.cardTitleReach))
        return try reader.make { () throws(ModelError) in
            try Card(
                id: id,
                meta: meta,
                canvasID: canvasID,
                frame: frame,
                title: title,
                sortKey: sortKey
            )
        }
    }
}
