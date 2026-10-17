import Testing

@testable import Model

/// Test targets can import Testing.
@Suite struct ModelTests {
    @Test("A value is itself") func identity() throws {
        let value = try #require(Int("1"))
        #expect(value == 1)
    }
}
