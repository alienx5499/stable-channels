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

    func testClassifyBIP21WithLightningFallbackPrioritizesLightning() {
        let invoiceStr = "lnbc1pn8g249pp5f6ytj32ty90jhvw69enf30hwfgdhyymjewywcmfjevflg6s4z86qdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdfjjzh2j9f7ye5qqqqryqqqqthqqpysp5mm832athgcal3m7h35sc29j63lmgzvwc5smfjh2es65elc2ns7dq9qrsgqu2xcje2gsnjp0wn97aknyd3h58an7sjj6nhcrm40846jxphv47958c6th76whmec8ttr2wmg6sxwchvxmsc00kqrzqcga6lvsf9jtqgqy5yexa"
        let bip21 = "bitcoin:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq?amount=0.001&lightning=\(invoiceStr)"
        let result = PaymentDestinationClassifier.classify(bip21)

        guard case .valid(let dest) = result else {
            XCTFail("Expected valid destination from BIP21")
            return
        }
        guard case .bolt11 = dest else {
            XCTFail("Expected .bolt11 to take priority over onchain fallback in BIP21")
            return
        }
    }

    func testClassifyBIP21UppercaseScheme() {
        let bip21 = "BITCOIN:bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        let result = PaymentDestinationClassifier.classify(bip21)
        guard case .valid(let dest) = result, case .onchain(let addr) = dest else {
            XCTFail("Expected valid onchain destination from uppercase BITCOIN: URI")
            return
        }
        XCTAssertEqual(addr, "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq")
    }

    func testClassifyLegacyAndTestnetOnchainAddresses() {
        let p2pkh = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"
        let p2sh = "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy"
        let testnet = "tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx"
        let regtest = "bcrt1q6z64a9asgt5g09unxmg2sqn03jy30mnx4q9e0m"

        XCTAssertEqual(PaymentDestinationClassifier.classify(p2pkh), .valid(.onchain(address: p2pkh)))
        XCTAssertEqual(PaymentDestinationClassifier.classify(p2sh), .valid(.onchain(address: p2sh)))
        XCTAssertEqual(PaymentDestinationClassifier.classify(testnet), .valid(.onchain(address: testnet)))
        XCTAssertEqual(PaymentDestinationClassifier.classify(regtest), .valid(.onchain(address: regtest)))
    }

    func testClassifyInvalidAddressLengthsAndCharacters() {
        // Less than 26 characters
        let tooShort = "1A1zP1eP5QGefi2DMPTfTL5SL"
        guard case .invalid = PaymentDestinationClassifier.classify(tooShort) else {
            XCTFail("Expected invalid for address under 26 characters")
            return
        }

        // More than 90 characters
        let tooLong = "bc1" + String(repeating: "q", count: 88)
        guard case .invalid = PaymentDestinationClassifier.classify(tooLong) else {
            XCTFail("Expected invalid for address over 90 characters")
            return
        }

        // Non-alphanumeric characters
        let nonAlphanumeric = "bc1qar0srrr7xfkvy5l643!@#$dnw9re59gtzzwf5mdq"
        guard case .invalid = PaymentDestinationClassifier.classify(nonAlphanumeric) else {
            XCTFail("Expected invalid for non-alphanumeric address")
            return
        }
    }

    func testClassifyLightningAddressEdgeCases() {
        // Valid plus-addressing
        let plusAddr = "satoshi+tips@walletofsatoshi.com"
        guard case .valid(let dest) = PaymentDestinationClassifier.classify(plusAddr),
              case .lightningAddress(let handle, let domain, _) = dest else {
            XCTFail("Expected valid lightning address with plus tag")
            return
        }
        XCTAssertEqual(handle, "satoshi+tips")
        XCTAssertEqual(domain, "walletofsatoshi.com")

        // Spaces inside
        guard case .invalid = PaymentDestinationClassifier.classify("satoshi @walletofsatoshi.com") else {
            XCTFail("Expected invalid for address with spaces")
            return
        }

        // Missing handle
        guard case .invalid = PaymentDestinationClassifier.classify("@walletofsatoshi.com") else {
            XCTFail("Expected invalid for missing handle")
            return
        }

        // Missing domain
        guard case .invalid = PaymentDestinationClassifier.classify("satoshi@") else {
            XCTFail("Expected invalid for missing domain")
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

    func testComputeEffectiveSatsWithZeroOrNegativePrice() {
        let model = SendFlowModel()
        model.amountUnit = .usd
        model.amountInputText = "100.00"

        // Zero price
        XCTAssertEqual(model.computeEffectiveSats(btcPrice: 0), 0)
        // Negative price
        XCTAssertEqual(model.computeEffectiveSats(btcPrice: -50_000), 0)
    }

    func testComputeEffectiveSatsWithMassiveAmount() {
        let model = SendFlowModel()
        model.amountUnit = .sats
        model.amountInputText = "99999999999999999999999999"
        // Double overflow / exceeds UInt64.max should return 0 safely without crashing
        XCTAssertEqual(model.computeEffectiveSats(btcPrice: 65_000), 0)
    }

    func testApplyPercentageWithZeroBalanceOrPrice() {
        let model = SendFlowModel()
        model.amountUnit = .usd
        model.applyPercentage(50, totalBalanceSats: 0, btcPrice: 65_000)
        XCTAssertEqual(model.amountInputText, "")

        model.applyPercentage(50, totalBalanceSats: 100_000, btcPrice: 0)
        XCTAssertEqual(model.amountInputText, "")
    }

    func testProceedFromAmountWithLNURLBounds() throws {
        let model = SendFlowModel()
        let appState = AppState()
        appState.lightningBalanceSats = 100_000
        model.destination = .lnurlPay(url: try XCTUnwrap(URL(string: "https://ln.tips/user")))
        model.lnurlParams = LNURLPayParams(
            tag: "payRequest",
            callback: "https://ln.tips/cb",
            minSendable: 1_000_000, // 1,000 sats
            maxSendable: 50_000_000, // 50,000 sats
            metadata: "[]",
            commentAllowed: nil
        )

        model.step = .amount
        model.amountUnit = .sats

        // Below minimum
        model.amountInputText = "500"
        model.proceedFromAmount(appState: appState)
        XCTAssertEqual(model.step, .amount)
        XCTAssertEqual(model.errorMessage, "Amount must be between 1000 and 50000 sats.")

        // Above maximum
        model.amountInputText = "60000"
        model.proceedFromAmount(appState: appState)
        XCTAssertEqual(model.step, .amount)
        XCTAssertEqual(model.errorMessage, "Amount must be between 1000 and 50000 sats.")

        // Exact minimum
        model.amountInputText = "1000"
        model.proceedFromAmount(appState: appState)
        XCTAssertEqual(model.step, .confirm)
        XCTAssertNil(model.errorMessage)
    }

    func testProceedFromAmount_blocksWhenBalanceIsZero() throws {
        let model = SendFlowModel()
        let appState = AppState()
        appState.lightningBalanceSats = 0
        model.destination = .lightningAddress(
            handle: "alice",
            domain: "tips.net",
            url: try XCTUnwrap(URL(string: "https://tips.net"))
        )
        model.step = .amount
        model.amountUnit = .usd
        model.amountInputText = "15.00"

        model.proceedFromAmount(appState: appState)

        XCTAssertEqual(model.step, .amount)
        XCTAssertEqual(model.errorMessage, "Insufficient balance. Your available balance is 0 sats.")
    }

    func testProceedFromAmount_blocksWhenAmountExceedsAvailableBalance() throws {
        let model = SendFlowModel()
        let appState = AppState()
        appState.lightningBalanceSats = 5_000
        model.destination = .lightningAddress(
            handle: "alice",
            domain: "tips.net",
            url: try XCTUnwrap(URL(string: "https://tips.net"))
        )
        model.step = .amount
        model.amountUnit = .sats
        model.amountInputText = "10000"

        model.proceedFromAmount(appState: appState)

        XCTAssertEqual(model.step, .amount)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.errorMessage?.contains("Insufficient balance") == true)
    }

    func testProceedFromAmount_allowsWhenAmountWithinBalance() throws {
        let model = SendFlowModel()
        let appState = AppState()
        appState.lightningBalanceSats = 50_000
        model.destination = .lightningAddress(
            handle: "alice",
            domain: "tips.net",
            url: try XCTUnwrap(URL(string: "https://tips.net"))
        )
        model.step = .amount
        model.amountUnit = .sats
        model.amountInputText = "10000"

        model.proceedFromAmount(appState: appState)

        XCTAssertEqual(model.step, .confirm)
        XCTAssertNil(model.errorMessage)
    }

    func testEstimatedFeeSats_calculatesExpectedFees() {
        let appState = AppState()
        let model = SendFlowModel()

        // Onchain target
        model.inputText = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        model.amountUnit = .sats
        model.amountInputText = "50000"
        model.feeRateSatVb = 10
        model.selectedFeeTier = .standard

        let onchainFee = model.estimatedFeeSats(appState: appState)
        // Standard onchain send: 140 vB * 10 sat/vB = 1400 sats
        XCTAssertEqual(onchainFee, 1_400)

        // Priority tier: 14 sat/vB -> 140 * 14 = 1960 sats
        model.selectedFeeTier = .priority
        XCTAssertEqual(model.estimatedFeeSats(appState: appState), 1_960)
    }

    func testIsInsufficientBalance_considersTotalDebitWithFee() {
        let appState = AppState()
        appState.spendableOnchainSats = 0
        let model = SendFlowModel()

        model.inputText = "bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq"
        model.amountUnit = .sats

        // When spendable balance is 0, any send is insufficient
        model.amountInputText = "100"
        XCTAssertTrue(model.isInsufficientBalance(appState: appState))
    }

    func testEffectiveFeeRate_tierScaling() {
        let model = SendFlowModel()
        model.feeRateSatVb = 20

        model.selectedFeeTier = .economy
        XCTAssertEqual(model.effectiveFeeRateSatVb, 14)

        model.selectedFeeTier = .standard
        XCTAssertEqual(model.effectiveFeeRateSatVb, 20)

        model.selectedFeeTier = .priority
        XCTAssertEqual(model.effectiveFeeRateSatVb, 28)
    }
}
