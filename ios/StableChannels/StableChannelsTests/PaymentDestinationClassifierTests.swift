import XCTest
@testable import StableChannels

final class PaymentDestinationClassifierTests: XCTestCase {
    func testClassifyLightningAddress() {
        let input = "satoshi@walletofsatoshi.com"
        let result = PaymentDestinationClassifier.classify(input)

        guard case .valid(let dest) = result else {
            XCTFail("Expected valid destination")
            return
        }

        guard case .lightningAddress(let handle, let domain, let url) = dest else {
            XCTFail("Expected .lightningAddress")
            return
        }

        XCTAssertEqual(handle, "satoshi")
        XCTAssertEqual(domain, "walletofsatoshi.com")
        XCTAssertEqual(url.absoluteString, "https://walletofsatoshi.com/.well-known/lnurlp/satoshi")
    }

    func testClassifyOnchainAddress() {
        let input = "bc1plvty62zgr8ae8vat0xyqrae0qgnlmcra5nnhpamhn46kdjuwh43q0wes3n"
        let result = PaymentDestinationClassifier.classify(input)

        guard case .valid(let dest) = result else {
            XCTFail("Expected valid destination")
            return
        }

        guard case .onchain(let addr) = dest else {
            XCTFail("Expected .onchain")
            return
        }

        XCTAssertEqual(addr, input)
    }

    func testClassifyBIP21WithOnchainAddress() {
        let input = "bitcoin:bc1plvty62zgr8ae8vat0xyqrae0qgnlmcra5nnhpamhn46kdjuwh43q0wes3n"
        let result = PaymentDestinationClassifier.classify(input)

        guard case .valid(let dest) = result else {
            XCTFail("Expected valid destination")
            return
        }

        guard case .onchain(let addr) = dest else {
            XCTFail("Expected .onchain")
            return
        }

        XCTAssertEqual(addr, "bc1plvty62zgr8ae8vat0xyqrae0qgnlmcra5nnhpamhn46kdjuwh43q0wes3n")
    }

    func testClassifyEmptyInput() {
        let result = PaymentDestinationClassifier.classify("   \n ")
        XCTAssertEqual(result, .empty)
    }

    func testClassifyInvalidInput() {
        let result = PaymentDestinationClassifier.classify("random_garbage_string")
        guard case .invalid = result else {
            XCTFail("Expected invalid result")
            return
        }
    }
}
