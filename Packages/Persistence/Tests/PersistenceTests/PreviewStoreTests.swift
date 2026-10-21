import Foundation
import Model
import Testing

@testable import Persistence

@Suite("Preview store")
struct PreviewStoreTests {
    private static let canvas = CanvasID(rawValue: UUID())

    private static func store(_ folder: TemporaryFolder) -> (PreviewStore, URL) {
        let previews = folder.url.appending(path: "previews", directoryHint: .isDirectory)
        return (PreviewStore(folder: previews), previews)
    }

    @Test("A written preview reads back, and a second write replaces it")
    func writeAndRead() async throws {
        let folder = try TemporaryFolder()
        let (store, previews) = Self.store(folder)
        try await store.write(Data([1, 2, 3]), for: Self.canvas)
        #expect(await store.read(Self.canvas) == Data([1, 2, 3]))
        try await store.write(Data([4]), for: Self.canvas)
        #expect(await store.read(Self.canvas) == Data([4]))
        let names = try FileManager().contentsOfDirectory(atPath: previews.path())
        #expect(names == ["\(Self.canvas.rawValue.uuidString).png"])
    }

    @Test("A missing file reads as nil")
    func missing() async throws {
        let folder = try TemporaryFolder()
        let (store, _) = Self.store(folder)
        #expect(await store.read(Self.canvas) == nil)
        try await store.remove(Self.canvas)
    }

    @Test(
        "A file up to the size limit reads, and a larger file is removed as damaged",
        arguments: [1, PreviewStore.maxFileSize, PreviewStore.maxFileSize + 1]
    )
    func sizeLimit(size: Int) async throws {
        let folder = try TemporaryFolder()
        let (store, previews) = Self.store(folder)
        try FileManager().createDirectory(at: previews, withIntermediateDirectories: true)
        let file = previews.appending(path: "\(Self.canvas.rawValue.uuidString).png")
        try Data(repeating: 7, count: size).write(to: file)
        let read = await store.read(Self.canvas)
        if size <= PreviewStore.maxFileSize {
            #expect(read?.count == size)
        } else {
            #expect(read == nil)
            #expect(!FileManager().fileExists(atPath: file.path()))
        }
    }

    @Test(
        "A write takes 1 byte to the limit and refuses 0 bytes and the limit plus one",
        arguments: [0, 1, PreviewStore.maxFileSize, PreviewStore.maxFileSize + 1]
    )
    func writeLimit(size: Int) async throws {
        let folder = try TemporaryFolder()
        let (store, _) = Self.store(folder)
        let data = Data(repeating: 1, count: size)
        if (1...PreviewStore.maxFileSize).contains(size) {
            try await store.write(data, for: Self.canvas)
            #expect(await store.read(Self.canvas) == data)
        } else {
            await #expect(throws: PersistenceError.self) {
                try await store.write(data, for: Self.canvas)
            }
            #expect(await store.read(Self.canvas) == nil)
        }
    }

    @Test("A file that is a folder reads as nil and is removed as damaged")
    func damaged() async throws {
        let folder = try TemporaryFolder()
        let (store, previews) = Self.store(folder)
        let file = previews.appending(path: "\(Self.canvas.rawValue.uuidString).png")
        try FileManager().createDirectory(at: file, withIntermediateDirectories: true)
        try Data([1]).write(to: file.appending(path: "inner"))
        #expect(await store.read(Self.canvas) == nil)
        #expect(!FileManager().fileExists(atPath: file.path()))
    }

    @Test("A remove takes one preview, and removeAll takes the folder with all previews")
    func remove() async throws {
        let folder = try TemporaryFolder()
        let (store, previews) = Self.store(folder)
        let other = CanvasID(rawValue: UUID())
        try await store.write(Data([1]), for: Self.canvas)
        try await store.write(Data([2]), for: other)
        try await store.remove(Self.canvas)
        #expect(await store.read(Self.canvas) == nil)
        #expect(await store.read(other) == Data([2]))
        try await store.removeAll()
        #expect(!FileManager().fileExists(atPath: previews.path()))
        #expect(await store.read(other) == nil)
        try await store.removeAll()
        try await store.write(Data([3]), for: other)
        #expect(await store.read(other) == Data([3]))
    }
}
