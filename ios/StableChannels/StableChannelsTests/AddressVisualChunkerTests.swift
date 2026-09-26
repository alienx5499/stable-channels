import XCTest
@testable import StableChannels

final class AddressVisualChunkerTests: XCTestCase {
    func testChunkingStandardAddress() {
        let addr = "bc1plvty62zgr8ae8vat0xyqrae0qgnlmcra5nnhpamhn46kdjuwh43q0wes3n"
        let result = AddressVisualChunker.chunkAddress(addr, chunkSize: 4)

        XCTAssertFalse(result.chunks.isEmpty)
        XCTAssertEqual(result.chunks[0].text, "bc1p")
        XCTAssertEqual(result.chunks[1].text, "lvty")
        XCTAssertTrue(result.chunks[0].isHighlighted)
        XCTAssertTrue(result.chunks[1].isHighlighted)

        // Middle chunks should not be highlighted
        XCTAssertFalse(result.chunks[2].isHighlighted)

        // Last 2 chunks should be highlighted
        let total = result.chunks.count
        XCTAssertTrue(result.chunks[total - 1].isHighlighted)
        XCTAssertTrue(result.chunks[total - 2].isHighlighted)
    }

    func testChunkingShortAddress() {
        let shortAddr = "1A1zP1eP"
        let result = AddressVisualChunker.chunkAddress(shortAddr, chunkSize: 4)

        XCTAssertEqual(result.chunks.count, 2)
        XCTAssertEqual(result.chunks[0].text, "1A1z")
        XCTAssertEqual(result.chunks[1].text, "P1eP")
        XCTAssertTrue(result.chunks[0].isHighlighted)
        XCTAssertTrue(result.chunks[1].isHighlighted)
    }

    func testEmptyAddress() {
        let result = AddressVisualChunker.chunkAddress("")
        XCTAssertTrue(result.chunks.isEmpty)
        XCTAssertEqual(result.formattedString, "")
    }
}
