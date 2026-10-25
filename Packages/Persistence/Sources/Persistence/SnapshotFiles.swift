import Foundation

/// The names, the ages, and the rotation of the snapshot files (storage.md 7.1 and 7.2, D-21).
struct SnapshotFiles {
    /// The number of daily snapshots that stay (D-21).
    static let keptCount = 7
    /// The age of the newest daily snapshot before the next one is due: 24 hours (D-21).
    static let interval: TimeInterval = 24 * 60 * 60
    /// The end of a partial file name. With `.sqlite`, it gives `LibraryMaintenance.partialSuffix`.
    static let partialExtension = ".partial"
    /// The most snapshots of one kind with the same second in their name: the counter of a
    /// name goes from 2 to this value (D-155). A tap of "Back up now" takes about a second.
    static let maxNameCounter = 99
    private static let prefix = "Pointer-"
    private static let preRestorePrefix = "Pointer-pre-restore-"
    private static let suffix = ".sqlite"
    /// `yyyy-MM-dd-HHmmss`: 17 characters.
    private static let stampLength = 17

    /// The `Backups/` folder.
    let backups: URL
    /// The `tmp/` folder of the app.
    let temporary: URL
    /// The time zone of the names.
    let timeZone: TimeZone
    private let files = FileManager()

    /// Returns the first name of a daily snapshot at `date` that `Backups/` does not hold:
    /// `Pointer-<stamp>.sqlite`, then `Pointer-<stamp>-2.sqlite`, and so on (D-155).
    ///
    /// - Throws: `PersistenceError.fileFailed` if all names up to `maxNameCounter` exist.
    func freeDailyName(at date: Date) throws(PersistenceError) -> String {
        try freeName(Self.prefix + stamp(at: date))
    }

    /// Returns the first name of a pre-restore snapshot at `date` that `Backups/` does not
    /// hold: `Pointer-pre-restore-<stamp>.sqlite`, with a counter as for a daily name (D-154).
    ///
    /// - Throws: `PersistenceError.fileFailed` if all names up to `maxNameCounter` exist.
    func freePreRestoreName(at date: Date) throws(PersistenceError) -> String {
        try freeName(Self.preRestorePrefix + stamp(at: date))
    }

    /// Returns the name after the highest counter of `base` in `Backups/`. A lower free name
    /// would sort as older than the snapshots of the same second, and the rotation could delete
    /// the new snapshot at once.
    private func freeName(_ base: String) throws(PersistenceError) -> String {
        precondition(base.hasPrefix(Self.prefix), "A snapshot name starts with Pointer-")
        var next = 1
        for counter in 1...Self.maxNameCounter where exists(Self.name(base, counter)) {
            next = counter + 1
        }
        guard next <= Self.maxNameCounter else {
            throw .fileFailed(reason: "\(Self.maxNameCounter) snapshots have the same second")
        }
        return Self.name(base, next)
    }

    private static func name(_ base: String, _ counter: Int) -> String {
        base + (counter == 1 ? "" : "-\(counter)") + suffix
    }

    /// Returns the stamp of `date` in the local time of the user: `yyyy-MM-dd-HHmmss`.
    private func stamp(at date: Date) -> String {
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
        assert(stamp.count == Self.stampLength, "The stamp \(stamp) has another length")
        return stamp
    }

    /// Returns the name of the snapshot before a migration from `oldVersion` (storage.md 6).
    static func preMigrationName(oldVersion: Int64) -> String {
        "\(prefix)pre-migration-v\(oldVersion)\(suffix)"
    }

    /// Returns true if `name` is the name of a daily snapshot, with or without a counter.
    static func isDaily(_ name: String) -> Bool {
        counter(of: name, prefix: prefix) != nil
    }

    /// Returns true if `name` is the name of a pre-restore snapshot (D-154).
    static func isPreRestore(_ name: String) -> Bool {
        counter(of: name, prefix: preRestorePrefix) != nil
    }

    /// Returns the counter of `<prefix><stamp>-<counter>.sqlite`, from 2 to `maxNameCounter`,
    /// 1 for `<prefix><stamp>.sqlite`, and `nil` for another name.
    private static func counter(of name: String, prefix: String) -> Int? {
        precondition(!prefix.isEmpty, "A snapshot name has a prefix")
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let middle = name.dropFirst(prefix.count).dropLast(suffix.count)
        let stamp = middle.prefix(stampLength)
        guard stamp.count == stampLength, stamp.allSatisfy(isStampCharacter) else { return nil }
        let rest = middle.dropFirst(stampLength)
        guard !rest.isEmpty else { return 1 }
        let digits = rest.dropFirst()
        guard rest.first == "-", !digits.hasPrefix("0"), digits.allSatisfy(\.isASCII),
            let counter = Int(digits), (2...maxNameCounter).contains(counter)
        else { return nil }
        return counter
    }

    private static func isStampCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isNumber || character == "-")
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
        // Snapshots of the same second have the same date, so the counter breaks the tie.
        let newestFirst = daily.sorted {
            ($0.date, Self.counter(of: $0.url.lastPathComponent, prefix: Self.prefix) ?? 0)
                > ($1.date, Self.counter(of: $1.url.lastPathComponent, prefix: Self.prefix) ?? 0)
        }
        assert(
            newestFirst.allSatisfy {
                $0.url.deletingLastPathComponent().standardizedFileURL
                    == backups.standardizedFileURL
            },
            "A daily snapshot outside \(backups.path(percentEncoded: false))"
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

    /// Deletes each pre-restore snapshot except `kept`, after `kept` exists (D-154).
    ///
    /// - Precondition: `kept` is the name of a pre-restore snapshot in `Backups/`.
    /// - Throws: `PersistenceError.fileFailed` if the folder does not list or a delete fails.
    func removePreRestoreSnapshots(except kept: String) throws(PersistenceError) {
        precondition(Self.isPreRestore(kept), "\(kept) is not a pre-restore name")
        precondition(exists(kept), "The new pre-restore snapshot exists before the old ones go")
        do {
            let names = try files.contentsOfDirectory(atPath: backups.path(percentEncoded: false))
            for name in names where Self.isPreRestore(name) && name != kept {
                try files.removeItem(at: backups.appending(path: name))
            }
        } catch {
            throw .fileFailed(reason: "cannot delete an old pre-restore snapshot: \(error)")
        }
    }

    /// Deletes the partial file of a failed snapshot at once, so that a full disk does not stay
    /// full and the next snapshot with that name works (D-155).
    ///
    /// - Precondition: `partial` is a partial file.
    /// - Throws: `PersistenceError.fileFailed` if the file exists and does not go.
    func removePartial(_ partial: URL) throws(PersistenceError) {
        precondition(partial.path.hasSuffix(Self.partialExtension), "Not a partial file")
        precondition(partial.deletingLastPathComponent().path == temporary.path, "Not in tmp")
        guard files.fileExists(atPath: partial.path(percentEncoded: false)) else { return }
        do {
            try files.removeItem(at: partial)
        } catch {
            throw .fileFailed(reason: "cannot delete a partial snapshot: \(error)")
        }
    }

    /// Returns true if a file named `name` exists in `Backups/`.
    func exists(_ name: String) -> Bool {
        files.fileExists(atPath: backups.appending(path: name).path(percentEncoded: false))
    }
}
