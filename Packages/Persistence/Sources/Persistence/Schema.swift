/// The schema versions of the library (storage.md sections 3.3 and 6).
enum Schema {
    /// The newest schema version that this app knows.
    static let currentVersion: Int64 = 1

    /// The tables of version 1, with the changes of D-29 and D-30. The text matches storage.md
    /// section 3.3.
    static let version1: StaticString = """
        CREATE TABLE library (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        ) STRICT;

        CREATE TABLE workspace (
            id         BLOB PRIMARY KEY,
            title      TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 120),
            sort_key   TEXT NOT NULL,
            created    BLOB NOT NULL,
            modified   BLOB NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
        ) STRICT;

        CREATE TABLE card (
            id         BLOB PRIMARY KEY,
            canvas_id  BLOB NOT NULL,
            x REAL NOT NULL, y REAL NOT NULL,
            width  REAL NOT NULL CHECK (width  >= 64),
            height REAL NOT NULL CHECK (height >= 48),
            title      TEXT CHECK (title IS NULL OR length(title) <= 120),
            sort_key   TEXT NOT NULL,
            created    BLOB NOT NULL,
            modified   BLOB NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
        ) STRICT;
        CREATE INDEX card_canvas ON card (canvas_id);

        CREATE TABLE text_box (
            id         BLOB PRIMARY KEY,
            canvas_id  BLOB NOT NULL,
            x REAL NOT NULL, y REAL NOT NULL,
            text       TEXT NOT NULL CHECK (length(text) BETWEEN 1 AND 10000),
            sort_key   TEXT NOT NULL,
            created    BLOB NOT NULL,
            modified   BLOB NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
        ) STRICT;
        CREATE INDEX text_box_canvas ON text_box (canvas_id);

        CREATE TABLE stroke (
            id          BLOB PRIMARY KEY,
            canvas_id   BLOB NOT NULL,
            created     BLOB NOT NULL,
            origin_x    REAL NOT NULL,
            origin_y    REAL NOT NULL,
            width       REAL NOT NULL,
            min_x REAL NOT NULL, min_y REAL NOT NULL,
            max_x REAL NOT NULL, max_y REAL NOT NULL,
            point_count INTEGER NOT NULL CHECK (point_count BETWEEN 2 AND 16384),
            points      BLOB NOT NULL,
            CHECK (length(points) = point_count * 16)
        ) STRICT;
        CREATE INDEX stroke_canvas ON stroke (canvas_id);

        CREATE TABLE stroke_erase (
            stroke_id  BLOB PRIMARY KEY REFERENCES stroke (id),
            erased     BLOB NOT NULL,
            modified   BLOB NOT NULL,
            is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1))
        ) STRICT;
        """

    /// Sets the schema version to 1. A pragma takes no parameter, so each version has its own.
    static let setVersion1: StaticString = "PRAGMA user_version = 1"
}
