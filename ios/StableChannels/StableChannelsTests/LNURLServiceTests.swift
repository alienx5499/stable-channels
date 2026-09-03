import XCTest
@testable import StableChannels

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
    }

    func testInvalidInputReturnsNil() {
        XCTAssertNil(service.parseInput("not an address"))
        XCTAssertNil(service.parseInput("bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"))
        XCTAssertNil(service.parseInput("lnbc100u1p3..."))
    }
}
