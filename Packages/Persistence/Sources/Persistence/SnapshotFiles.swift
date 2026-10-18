import Foundation

/// The names, the ages, and the rotation of the snapshot files (storage.md 7.1 and 7.2, D-21).
struct SnapshotFiles {
    /// The number of daily snapshots that stay (D-21).
    static let keptCount = 7
    /// The age of the newest daily snapshot before the next one is due: 24 hours (D-21).
    static let interval: TimeInterval = 24 * 60 * 60
    /// The end of a partial file name. With `.sqlite`, it gives `LibraryMaintenance.partialSuffix`.
    static let partialExtension = ".partial"
    private static let prefix = "Pointer-"
    private static let suffix = ".sqlite"
    /// `Pointer-yyyy-MM-dd-HHmmss.sqlite`: 8 + 17 + 7 characters.
    private static let dailyNameLength = 32

    let backups: URL
    let temporary: URL
    let timeZone: TimeZone
    private let files = FileManager()

    /// Returns the name of the daily snapshot at `date`, in the local time of the user.
    func dailyName(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let stamp = String(
            format: "%04d-%02d-%02d-%02d%02d%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0,
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
        let name = Self.prefix + stamp + Self.suffix
        assert(Self.isDaily(name), "The daily name \(name) does not match its own pattern")
        return name
    }

    /// Returns the name of the snapshot before a migration from `oldVersion` (storage.md 6).
    static func preMigrationName(oldVersion: Int64) -> String {
        "\(prefix)pre-migration-v\(oldVersion)\(suffix)"
    }

    /// Returns true if `name` is the name of a daily snapshot.
    static func isDaily(_ name: String) -> Bool {
        guard name.count == dailyNameLength, name.hasPrefix(prefix), name.hasSuffix(suffix) else {
            return false
        }
        let stamp = name.dropFirst(prefix.count).dropLast(suffix.count)
        return stamp.allSatisfy { $0.isASCII && ($0.isNumber || $0 == "-") }
    }

    /// Returns the daily snapshots with their change dates, newest first.
    ///
    /// - Throws: `PersistenceError.fileFailed` if the folder does not list. A missing folder
    ///   gives no snapshots.
    func dailySnapshots() throws(PersistenceError) -> [(url: URL, date: Date)] {
        guard files.fileExists(atPath: backups.path(percentEncoded: false)) else { return [] }
        let urls: [URL]
        do {
            urls = try files.contentsOfDirectory(
                at: backups,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )
        } catch {
            throw .fileFailed(reason: "cannot list Backups: \(error)")
        }
        let daily = urls.filter { Self.isDaily($0.lastPathComponent) }.map { url in
            let date =
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (url: url, date: date)
        }
        let newestFirst = daily.sorted { $0.date > $1.date }
        assert(
            zip(newestFirst, newestFirst.dropFirst()).allSatisfy { $0.date >= $1.date },
            "The snapshots are not newest first"
        )
        return newestFirst
    }

    /// Moves a finished file from `tmp/` into `Backups/` with one rename (storage.md 7.1). The
    /// change date of the file becomes `date`, so the age of the snapshots uses the clock of the
    /// writer.
    ///
    /// - Throws: `PersistenceError.fileFailed` if the folder, the date, or the rename fails.
    func publish(_ partial: URL, as name: String, at date: Date) throws(PersistenceError) -> URL {
        precondition(partial.path.hasSuffix(Self.partialExtension), "Not a partial file")
        let target = backups.appending(path: name)
        do {
            try files.createDirectory(at: backups, withIntermediateDirectories: true)
            try files.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: partial.path(percentEncoded: false)
            )
            try files.moveItem(at: partial, to: target)
        } catch {
            throw .fileFailed(reason: "cannot move the snapshot into Backups: \(error)")
        }
        assert(exists(name), "The snapshot \(name) is not in Backups after the rename")
        return target
    }

    /// Deletes the daily snapshots after the newest `keptCount`.
    ///
    /// - Throws: `PersistenceError.fileFailed` if a delete fails.
    func removeOldSnapshots() throws(PersistenceError) {
        let old = try dailySnapshots().dropFirst(Self.keptCount)
        for snapshot in old {
            do {
                try files.removeItem(at: snapshot.url)
            } catch {
                throw .fileFailed(reason: "cannot delete an old snapshot: \(error)")
            }
        }
        assert(
            (try? dailySnapshots().count).map { $0 <= Self.keptCount } ?? true,
            "More than \(Self.keptCount) daily snapshots stay"
        )
    }

    /// Returns true if a file named `name` exists in `Backups/`.
    func exists(_ name: String) -> Bool {
        files.fileExists(atPath: backups.appending(path: name).path(percentEncoded: false))
    }
}
