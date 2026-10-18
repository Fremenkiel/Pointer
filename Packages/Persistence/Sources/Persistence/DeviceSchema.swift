/// The schema of `device.sqlite` (storage.md section 10, D-53).
enum DeviceSchema {
    /// The tables of version 1. The text matches storage.md section 10.
    static let version1: StaticString = """
        CREATE TABLE device (
            key   TEXT PRIMARY KEY,
            value BLOB NOT NULL
        ) STRICT;

        CREATE TABLE camera (
            canvas_id BLOB PRIMARY KEY,
            center_x  REAL NOT NULL,
            center_y  REAL NOT NULL,
            zoom      REAL NOT NULL CHECK (zoom BETWEEN 0.25 AND 8.0),
            used      INTEGER NOT NULL
        ) STRICT;
        CREATE INDEX camera_used ON camera (used);
        """

    /// The migrations of the device file, in order.
    static let migrations = [
        Migration(version: 1, statements: version1, setVersion: "PRAGMA user_version = 1")
    ]
}
