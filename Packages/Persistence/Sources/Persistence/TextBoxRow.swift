import Geometry
import Model

/// The SQL and the codec of the `text_box` table (storage.md section 3.3).
enum TextBoxRow {
    /// The number of parameters of the write statement.
    static let parameterCount: Int32 = 9
    /// The number of columns of the read statement.
    static let columnCount: Int32 = 9

    /// Writes a text box. A row with the same ID takes the new values.
    static let upsert: StaticString = """
        INSERT INTO text_box (id, canvas_id, x, y, text, sort_key, created, modified, is_deleted)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (id) DO UPDATE SET canvas_id = excluded.canvas_id, x = excluded.x,
            y = excluded.y, text = excluded.text, sort_key = excluded.sort_key,
            modified = excluded.modified, is_deleted = excluded.is_deleted
        """

    /// Reads the live text boxes of one canvas.
    static let selectLive: StaticString = """
        SELECT id, canvas_id, x, y, text, sort_key, created, modified, is_deleted
        FROM text_box WHERE canvas_id = ? AND is_deleted = 0
        """

    /// Counts the live text boxes of one canvas, for the report of a load past the limit.
    static let countLive: StaticString = """
        SELECT count(*) FROM text_box WHERE canvas_id = ? AND is_deleted = 0
        """

    /// Binds `textBox` to the parameters of `upsert`.
    ///
    /// - Throws: `PersistenceError.sqlite` if a bind fails.
    static func bind(_ textBox: TextBox, to statement: SQLiteStatement) throws(PersistenceError) {
        precondition(statement.parameterCount == parameterCount, "Not a text box write")
        var binder = try RowBinder(statement)
        try binder.bind(textBox.id)
        try binder.bind(textBox.canvasID)
        try binder.bind(textBox.origin.x)
        try binder.bind(textBox.origin.y)
        try binder.bind(textBox.text)
        try binder.bind(textBox.sortKey.rawValue)
        try binder.bind(textBox.meta)
        assert(binder.count == statement.parameterCount, "Text box binds all parameters")
    }

    /// Reads the current row of `selectLive`.
    ///
    /// - Throws: `PersistenceError.corruptRow` if a column does not give a valid text box.
    static func read(from statement: SQLiteStatement) throws(PersistenceError) -> TextBox {
        precondition(statement.columnCount == columnCount, "Not a text box read")
        var reader = RowReader(statement, table: "text_box")
        let id: TextBoxID = try reader.identifier()
        let canvasID: CanvasID = try reader.identifier()
        let origin = Point(x: try reader.double(), y: try reader.double())
        // The text length and `TextStyle.maxWidth` bound the size, so the origin is enough.
        try reader.checkBounds(Rect(origin: origin, size: .zero))
        let text = try reader.string()
        let sortKey = try reader.sortKey()
        let meta = try reader.meta()
        let textBox = try reader.make { () throws(ModelError) in
            try TextBox(
                id: id,
                meta: meta,
                canvasID: canvasID,
                origin: origin,
                text: text,
                sortKey: sortKey
            )
        }
        assert(!textBox.meta.isDeleted, "The live read gave tombstone \(textBox.id)")
        return textBox
    }
}
