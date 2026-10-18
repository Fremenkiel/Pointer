/// The prepared statements of the device state store, compiled once at open.
final class DeviceStatements {
    let begin: SQLiteStatement
    let commit: SQLiteStatement
    let rollback: SQLiteStatement
    let selectValue: SQLiteStatement
    let upsertValue: SQLiteStatement
    let deleteValue: SQLiteStatement
    let selectCamera: SQLiteStatement
    let upsertCamera: SQLiteStatement
    let trimCameras: SQLiteStatement

    /// Compiles all statements on `connection`.
    ///
    /// - Throws: `PersistenceError.sqlite` if a statement does not compile.
    init(_ connection: SQLiteConnection) throws(PersistenceError) {
        begin = try connection.prepare("BEGIN IMMEDIATE")
        commit = try connection.prepare("COMMIT")
        rollback = try connection.prepare("ROLLBACK")
        selectValue = try connection.prepare("SELECT value FROM device WHERE key = ?")
        upsertValue = try connection.prepare(
            """
            INSERT INTO device (key, value) VALUES (?, ?)
            ON CONFLICT (key) DO UPDATE SET value = excluded.value
            """
        )
        deleteValue = try connection.prepare("DELETE FROM device WHERE key = ?")
        selectCamera = try connection.prepare(
            "SELECT center_x, center_y, zoom FROM camera WHERE canvas_id = ?"
        )
        // `used` grows by 1 with each write, so a change of the system time does not change the
        // order (storage.md section 10).
        upsertCamera = try connection.prepare(
            """
            INSERT INTO camera (canvas_id, center_x, center_y, zoom, used)
            VALUES (?, ?, ?, ?, (SELECT coalesce(max(used), 0) + 1 FROM camera))
            ON CONFLICT (canvas_id) DO UPDATE SET center_x = excluded.center_x,
                center_y = excluded.center_y, zoom = excluded.zoom, used = excluded.used
            """
        )
        trimCameras = try connection.prepare(
            """
            DELETE FROM camera WHERE canvas_id NOT IN (
                SELECT canvas_id FROM camera ORDER BY used DESC LIMIT ?)
            """
        )
        assert(upsertCamera.parameterCount == 4, "A camera write binds 4 values")
        assert(selectCamera.columnCount == 3, "A camera read gives 3 values")
    }
}
