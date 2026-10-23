import Foundation
import Testing

@testable import Export

@Suite("PDF buffer")
struct PDFBufferTests {
    @Test("The data of a finished PDF shares the bytes of its buffer")
    func dataSharesTheBuffer() throws {
        let buffer = try #require(NSMutableData(length: 4_096))
        let bytes: [UInt8] = [1, 2, 3, 4]
        buffer.replaceBytes(in: NSRange(location: 0, length: 4), withBytes: bytes)
        // Only the addresses are compared, while `buffer` is alive.
        let bufferAddress = UInt(bitPattern: buffer.mutableBytes)
        let data = PDFExporter.data(sharing: buffer)
        let dataAddress = data.withUnsafeBytes { UInt(bitPattern: $0.baseAddress) }
        #expect(dataAddress == bufferAddress)
        #expect(data.count == 4_096)
        #expect(Array(data.prefix(4)) == [1, 2, 3, 4])
    }
}
