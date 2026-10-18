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
