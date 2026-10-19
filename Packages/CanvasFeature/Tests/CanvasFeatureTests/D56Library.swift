import Foundation
import Geometry
import Model
import Persistence
import XCTest

/// A library in a temporary folder with the content of D-56 on one canvas: 20,000 strokes of
/// 300 points, 5,000 cards, and 5,000 text boxes. The open test and the memory test of the
/// canvas use it.
@MainActor
struct D56Library {
    /// The content of D-56.
    static let strokeCount = 20_000
    static let pointsPerStroke = 300
    static let cardCount = 5_000
    static let textBoxCount = 5_000
    private static let textLength = 200
    /// The strokes of one save while the library fills.
    private static let batch = 1_000

    /// The repository of the library. The app keeps one open and opens each canvas through it.
    let repository: SQLiteLibraryRepository
    /// The canvas with the content.
    let canvas: CanvasID
    private let folder: URL

    /// Makes the folder, opens the library, and fills the canvas.
    ///
    /// - Throws: An error of the folder or of the library.
    static func make() async throws -> D56Library {
        let folder = try makeFolder()
        let configuration = SQLiteLibraryRepository.Configuration(
            databasePath: folder.appending(path: "library.sqlite").path(percentEncoded: false),
            temporaryFolder: folder,
            device: DeviceID(rawValue: UUID()),
            wallClock: SystemWallClock(),
            timer: ContinuousSaveTimer()
        )
        let repository = SQLiteLibraryRepository(configuration: configuration) { _ in }
        let library = D56Library(
            repository: repository,
            canvas: CanvasID(rawValue: UUID()),
            folder: folder
        )
        _ = try await repository.open { _ in }
        try await library.fill(device: configuration.device)
        return library
    }

    /// Removes the folder of the library, about 95 MB (D-60).
    func remove() {
        do {
            // swiftlint:disable:next arch_04_file_system
            try FileManager().removeItem(at: folder)
        } catch {
            XCTFail("The test folder stays behind: \(error)")
        }
    }

    private func fill(device: DeviceID) async throws {
        let points = InkPoints(
            (0..<Self.pointsPerStroke).map {
                InkPoint(x: Float($0) / 10, y: Float($0 % 7), force: 0.5, time: 0)
            }
        )
        for start in stride(from: 0, to: Self.strokeCount, by: Self.batch) {
            let rows = (start..<start + Self.batch).map { index in
                LibraryChange.stroke(
                    Stroke(
                        id: StrokeID(rawValue: UUID()),
                        canvasID: canvas,
                        created: HybridTimestamp(
                            wallMillis: 1,
                            counter: UInt32(index),
                            device: device
                        ),
                        origin: Point(
                            x: Double(index % 200) * 40 - 4_000,
                            y: Double(index / 200) * 40 - 2_000
                        ),
                        width: 2,
                        points: points
                    )
                )
            }
            try await repository.send(rows)
            try await repository.saveNow()
        }
        try await repository.send(try nodes(device))
        try await repository.saveNow()
    }

    private func nodes(_ device: DeviceID) throws -> [LibraryChange] {
        let meta = RecordMeta(created: HybridTimestamp(wallMillis: 2, counter: 0, device: device))
        let key = try FractionalIndex(rawValue: "V")
        let text = String(repeating: "node ", count: Self.textLength / 5)
        let cards = try (0..<Self.cardCount).map { index in
            LibraryChange.card(
                try Card(
                    id: CardID(rawValue: UUID()),
                    meta: meta,
                    canvasID: canvas,
                    frame: Rect(
                        origin: Point(x: Double(index % 100) * 120, y: Double(index / 100) * 90),
                        size: Size(width: 100, height: 70)
                    ),
                    title: "Card \(index)",
                    sortKey: key
                )
            )
        }
        let textBoxes = try (0..<Self.textBoxCount).map { index in
            LibraryChange.textBox(
                try TextBox(
                    id: TextBoxID(rawValue: UUID()),
                    meta: meta,
                    canvasID: canvas,
                    origin: Point(
                        x: Double(index % 100) * 120,
                        y: Double(index / 100) * 90 + 5_000
                    ),
                    text: text,
                    sortKey: key
                )
            )
        }
        return cards + textBoxes
    }

    /// Makes the folder of the library. The product owner allowed this file access in the
    /// test on 2026-10-18 (D-60).
    private static func makeFolder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(
            path: "CanvasOpen-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        // swiftlint:disable:next arch_04_file_system
        try FileManager().createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
