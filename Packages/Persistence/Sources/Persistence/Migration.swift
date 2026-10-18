/// One schema change: SQL that runs in the migration transaction (storage.md section 6).
struct Migration {
    /// The schema version after the change.
    let version: Int64
    /// The statements of the change.
    let statements: StaticString
    /// The pragma that sets `user_version` to `version`. A pragma takes no parameter.
    let setVersion: StaticString

    /// The migrations of the library, in order.
    static let library = [
        Migration(version: 1, statements: Schema.version1, setVersion: Schema.setVersion1)
    ]
}
