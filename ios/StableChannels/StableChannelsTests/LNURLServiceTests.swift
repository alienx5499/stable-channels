import XCTest
@testable import StableChannels

final class MockLNURLService: LNURLServiceProtocol {
    var stubbedParams: LNURLPayParams?
    var stubbedInvoiceResponse: LNURLPayInvoiceResponse?
    var shouldThrowError: Error?

    func fetchPayParams(from _: URL) async throws -> LNURLPayParams {
        if let error = shouldThrowError {
            throw error
        }
        guard let params = stubbedParams else {
            throw LNURLError.invalidResponse
        }
        return params
    }

    func fetchInvoice(callback _: String, amountMsat _: UInt64,
                      comment _: String?) async throws -> LNURLPayInvoiceResponse {
        if let error = shouldThrowError {
            throw error
        }
        guard let response = stubbedInvoiceResponse else {
            throw LNURLError.invalidResponse
        }
        return response
    }
}

final class LNURLServiceTests: XCTestCase {
    func testMetadataParsing() {
        let metadataJSON = "[[\"text/plain\",\"Coffee Tip\"],[\"image/png;base64\",\"abc123def\"]]"
        let params = LNURLPayParams(
            tag: "payRequest",
            callback: "https://service.com/callback",
            minSendable: 1000,
            maxSendable: 21_000_000_000,
            metadata: metadataJSON,
            commentAllowed: 140
        )

        XCTAssertEqual(params.minSats, 1)
        XCTAssertEqual(params.maxSats, 21_000_000)
        XCTAssertEqual(params.plainTextDescription, "Coffee Tip")
        XCTAssertFalse(params.hasCustomSendBounds)
    }

    func testCustomBoundsDetection() {
        let restrictedParams = LNURLPayParams(
            tag: "payRequest",
            callback: "https://service.com/callback",
            minSendable: 50_000,
            maxSendable: 1_000_000,
            metadata: "[[\"text/plain\",\"Coffee\"]]",
            commentAllowed: nil
        )

        XCTAssertTrue(restrictedParams.hasCustomSendBounds)
        XCTAssertEqual(restrictedParams.minSats, 50)
        XCTAssertEqual(restrictedParams.maxSats, 1000)
    }

    func testMockServiceSubstitution() async throws {
        let mock = MockLNURLService()
        mock.stubbedParams = LNURLPayParams(
            tag: "payRequest",
            callback: "https://test.com/cb",
            minSendable: 1000,
            maxSendable: 10000,
            metadata: "[[\"text/plain\",\"Test\"]]",
            commentAllowed: nil
        )

        let url = try XCTUnwrap(URL(string: "https://test.com/lnurlp"))
        let params = try await mock.fetchPayParams(from: url)
        XCTAssertEqual(params.callback, "https://test.com/cb")
    }
}
