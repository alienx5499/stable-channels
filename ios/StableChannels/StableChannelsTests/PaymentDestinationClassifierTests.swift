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

@MainActor
final class SendFlowModelTests: XCTestCase {
    func testComputeEffectiveSatsAcrossUnits() {
        let model = SendFlowModel()
        let btcPrice: Double = 65_000

        // USD mode
        model.amountUnit = .usd
        model.amountInputText = "65.00"
        XCTAssertEqual(model.computeEffectiveSats(btcPrice: btcPrice), 100_000)

        // Sats mode
        model.amountUnit = .sats
        model.amountInputText = "50000"
        XCTAssertEqual(model.computeEffectiveSats(btcPrice: btcPrice), 50_000)

        // BTC mode
        model.amountUnit = .btc
        model.amountInputText = "0.001"
        XCTAssertEqual(model.computeEffectiveSats(btcPrice: btcPrice), 100_000)
    }

    func testSwitchUnitPreservesValue() {
        let model = SendFlowModel()
        let btcPrice: Double = 65_000

        model.amountUnit = .usd
        model.amountInputText = "65.00"

        model.switchUnit(to: .sats, btcPrice: btcPrice)
        XCTAssertEqual(model.amountUnit, .sats)
        XCTAssertEqual(model.amountInputText, "100000")

        model.switchUnit(to: .btc, btcPrice: btcPrice)
        XCTAssertEqual(model.amountUnit, .btc)
        XCTAssertEqual(model.amountInputText, "0.00100000")

        model.switchUnit(to: .usd, btcPrice: btcPrice)
        XCTAssertEqual(model.amountUnit, .usd)
        XCTAssertEqual(model.amountInputText, "65.00")
    }

    func testApplyPercentageAcrossUnits() {
        let model = SendFlowModel()
        let btcPrice: Double = 65_000
        let totalSats: UInt64 = 200_000

        model.amountUnit = .sats
        model.applyPercentage(50, totalBalanceSats: totalSats, btcPrice: btcPrice)
        XCTAssertEqual(model.amountInputText, "100000")

        model.amountUnit = .usd
        model.applyPercentage(50, totalBalanceSats: totalSats, btcPrice: btcPrice)
        XCTAssertEqual(model.amountInputText, "65.00")

        model.amountUnit = .btc
        model.applyPercentage(50, totalBalanceSats: totalSats, btcPrice: btcPrice)
        XCTAssertEqual(model.amountInputText, "0.00100000")
    }

    func testSendAmountUnitProperties() {
        XCTAssertEqual(SendAmountUnit.usd.maxDecimals, 2)
        XCTAssertEqual(SendAmountUnit.sats.maxDecimals, 0)
        XCTAssertEqual(SendAmountUnit.btc.maxDecimals, 8)

        XCTAssertEqual(SendAmountUnit.usd.symbolOrSuffix, "$")
        XCTAssertEqual(SendAmountUnit.sats.symbolOrSuffix, "sats")
        XCTAssertEqual(SendAmountUnit.btc.symbolOrSuffix, "BTC")

        XCTAssertEqual(SendAmountUnit.usd.menuTitle, "US Dollar (USD)")
        XCTAssertEqual(SendAmountUnit.sats.menuTitle, "Satoshis (sats)")
        XCTAssertEqual(SendAmountUnit.btc.menuTitle, "Bitcoin (BTC)")
    }

    func testNormalizeAmountInput() {
        let model = SendFlowModel()

        // USD normalization
        model.amountUnit = .usd
        model.amountInputText = "12"
        model.normalizeAmountInput()
        XCTAssertEqual(model.amountInputText, "12.00")

        model.amountInputText = "12.5"
        model.normalizeAmountInput()
        XCTAssertEqual(model.amountInputText, "12.50")

        model.amountInputText = "12."
        model.normalizeAmountInput()
        XCTAssertEqual(model.amountInputText, "12.00")

        model.amountInputText = ".5"
        model.normalizeAmountInput()
        XCTAssertEqual(model.amountInputText, "0.50")

        // Sats normalization
        model.amountUnit = .sats
        model.amountInputText = "0050"
        model.normalizeAmountInput()
        XCTAssertEqual(model.amountInputText, "50")

        // BTC normalization
        model.amountUnit = .btc
        model.amountInputText = ".001"
        model.normalizeAmountInput()
        XCTAssertEqual(model.amountInputText, "0.001")
    }
}
