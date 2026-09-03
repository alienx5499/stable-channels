import XCTest
@testable import StableChannels

// MARK: - Mock LNURL Service (Liskov Substitution & Dependency Inversion)

final class MockLNURLService: LNURLServiceProtocol {
    var stubbedTarget: LNURLTarget?
    var stubbedParams: LNURLPayParams?
    var stubbedInvoiceResponse: LNURLPayInvoiceResponse?
    var shouldThrowError: Error?

    func parseInput(_: String) -> LNURLTarget? {
        stubbedTarget
    }

    func fetchPayParams(from _: LNURLTarget) async throws -> LNURLPayParams {
        if let error = shouldThrowError {
            throw error
        }
        guard let params = stubbedParams else {
            throw LNURLService.LNURLError.invalidResponse
        }
        return params
    }

    func fetchInvoice(callback _: String, amountMsat _: UInt64,
                      comment _: String?) async throws -> LNURLPayInvoiceResponse {
        if let error = shouldThrowError {
            throw error
        }
        guard let response = stubbedInvoiceResponse else {
            throw LNURLService.LNURLError.invalidResponse
        }
        return response
    }
}

// MARK: - Tests

final class LNURLServiceTests: XCTestCase {
    var service: LNURLService!

    override func setUp() {
        super.setUp()
        service = LNURLService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testParseLightningAddress() {
        let input = "satoshi@walletofsatoshi.com"
        let target = service.parseInput(input)

        guard case let .lightningAddress(handle, domain, url) = target else {
            XCTFail("Expected .lightningAddress target")
            return
        }

        XCTAssertEqual(handle, "satoshi")
        XCTAssertEqual(domain, "walletofsatoshi.com")
        XCTAssertEqual(url.absoluteString, "https://walletofsatoshi.com/.well-known/lnurlp/satoshi")
        XCTAssertEqual(target?.displayDestination, "satoshi@walletofsatoshi.com")
    }

    func testParseLightningAddressWithLightningPrefix() {
        let input = "lightning:user@getalby.com"
        let target = service.parseInput(input)

        guard case let .lightningAddress(handle, domain, url) = target else {
            XCTFail("Expected .lightningAddress target")
            return
        }

        XCTAssertEqual(handle, "user")
        XCTAssertEqual(domain, "getalby.com")
        XCTAssertEqual(url.absoluteString, "https://getalby.com/.well-known/lnurlp/user")
    }

    func testParseDirectLNURLURL() {
        let input = "https://domain.com/.well-known/lnurlp/alice"
        let target = service.parseInput(input)

        guard case let .lnurlPay(url) = target else {
            XCTFail("Expected .lnurlPay target")
            return
        }

        XCTAssertEqual(url.absoluteString, "https://domain.com/.well-known/lnurlp/alice")
    }

    func testMetadataParsing() {
        let metadataJSON = "[[\"text/plain\",\"Donation for satoshi\"],[\"image/png;base64\",\"iVBORw0KGgoAAA...\"]]"
        let params = LNURLPayParams(
            tag: "payRequest",
            callback: "https://service.com/api/v1/lnurl/pay/callback",
            minSendable: 1000,
            maxSendable: 100000000,
            metadata: metadataJSON,
            commentAllowed: 140,
            nostrPubkey: nil,
            allowsNostr: nil
        )

        XCTAssertEqual(params.minSats, 1)
        XCTAssertEqual(params.maxSats, 100000)
        XCTAssertEqual(params.plainTextDescription, "Donation for satoshi")
        XCTAssertFalse(params.hasCustomSendBounds, "1 to 100,000 sats is within typical open bounds")
    }

    func testCustomBoundsDetection() {
        let restrictedParams = LNURLPayParams(
            tag: "payRequest",
            callback: "https://service.com/api/v1/lnurl/pay/callback",
            minSendable: 50_000, // 50 sats
            maxSendable: 1_000_000, // 1000 sats
            metadata: "[[\"text/plain\",\"Coffee shop\"]]",
            commentAllowed: nil,
            nostrPubkey: nil,
            allowsNostr: nil
        )

        XCTAssertTrue(restrictedParams.hasCustomSendBounds, "Custom min/max should be recognized as custom bounds")
        XCTAssertEqual(restrictedParams.minSats, 50)
        XCTAssertEqual(restrictedParams.maxSats, 1000)
    }

    func testMockServiceSubstitution() async throws {
        let mock = MockLNURLService()
        let expectedTarget = LNURLTarget.lightningAddress(
            handle: "bob",
            domain: "test.com",
            url: try XCTUnwrap(URL(string: "https://test.com/.well-known/lnurlp/bob"))
        )
        mock.stubbedTarget = expectedTarget
        mock.stubbedParams = LNURLPayParams(
            tag: "payRequest",
            callback: "https://test.com/cb",
            minSendable: 1000,
            maxSendable: 10000,
            metadata: "[[\"text/plain\",\"Test\"]]",
            commentAllowed: nil,
            nostrPubkey: nil,
            allowsNostr: nil
        )

        let parsed = mock.parseInput("bob@test.com")
        XCTAssertEqual(parsed, expectedTarget)

        let params = try await mock.fetchPayParams(from: expectedTarget)
        XCTAssertEqual(params.callback, "https://test.com/cb")
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(service.parseInput("not an address"))
        XCTAssertNil(service.parseInput("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"))
        XCTAssertNil(service.parseInput("lnbc100u1p3..."))
    }
}
