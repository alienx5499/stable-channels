import XCTest
@testable import StableChannels

final class StabilityServiceTests: XCTestCase {
    // MARK: - Helper

    private func testSC(expectedUSD: Double, price: Double, receiverSats: UInt64) -> StableChannel {
        let backing: UInt64 = price > 0
            ? UInt64(expectedUSD / price * 100_000_000.0)
            : 0
        var sc = StableChannel.default
        sc.expectedUSD = USD(amount: expectedUSD)
        sc.backingSats = backing
        sc.latestPrice = price
        sc.stableReceiverBTC = Bitcoin(sats: receiverSats)
        sc.isStableReceiver = true
        return sc
    }

    // MARK: - reconcileOutgoing

    func testOutgoingNoStablePosition() {
        var sc = testSC(expectedUSD: 0.0, price: 100_000.0, receiverSats: 500_000)
        XCTAssertNil(StabilityService.reconcileOutgoing(&sc, price: 100_000.0))
    }

    func testOutgoingCoveredByNative() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 800_000)
        XCTAssertNil(StabilityService.reconcileOutgoing(&sc, price: 100_000.0))
        XCTAssertEqual(sc.expectedUSD.amount, 500.0)
    }

    func testOutgoingDeductsFromStable() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_200_000)
        let deducted = try XCTUnwrap(StabilityService.reconcileOutgoing(&sc, price: 100_000.0))
        XCTAssertGreaterThan(deducted, 0)
        XCTAssertLessThan(sc.expectedUSD.amount, 500.0)
    }

    func testOutgoingFullyDrainsStable() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_200_000)
        let deducted = try XCTUnwrap(StabilityService.reconcileOutgoing(&sc, price: 100_000.0))
        XCTAssertGreaterThan(deducted, 0)
        XCTAssertEqual(sc.expectedUSD.amount, 0.0, accuracy: 0.01)
    }

    func testOutgoingZeroPrice() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_200_000)
        XCTAssertNil(StabilityService.reconcileOutgoing(&sc, price: 0.0))
    }

    func testOutgoingBackingClampedToUserBalance() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 600_000)
        let d1 = try XCTUnwrap(StabilityService.reconcileOutgoing(&sc, price: 100_000.0))
        let d2 = try XCTUnwrap(StabilityService.reconcileOutgoing(&sc, price: 200_000.0))
        XCTAssertEqual(sc.backingSats, 0)
    }

    // MARK: - reconcileForwarded

    func testForwardedNoStablePosition() {
        var sc = testSC(expectedUSD: 0.0, price: 100_000.0, receiverSats: 500_000)
        XCTAssertNil(StabilityService.reconcileForwarded(
            _: &sc,
            userSats: 500_000,
            totalForwardedSats: 100_000,
            price: 100_000.0
        ))
    }

    func testForwardedCoveredByNative() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        XCTAssertNil(StabilityService.reconcileForwarded(
            _: &sc,
            userSats: 1_000_000,
            totalForwardedSats: 500_000,
            price: 100_000.0
        ))
        XCTAssertEqual(sc.expectedUSD.amount, 500.0)
    }

    func testForwardedDeductsOverflow() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let deducted = try XCTUnwrap(StabilityService.reconcileForwarded(
            _: &sc,
            userSats: 800_000,
            totalForwardedSats: 1_200_000,
            price: 100_000.0
        ))
        XCTAssertGreaterThan(deducted, 0)
        XCTAssertLessThan(sc.expectedUSD.amount, 500.0)
    }

    func testForwardedFullyDrains() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let deducted = try XCTUnwrap(StabilityService.reconcileForwarded(
            _: &sc,
            userSats: 800_000,
            totalForwardedSats: 1_500_000,
            price: 100_000.0
        ))
        XCTAssertEqual(sc.expectedUSD.amount, 0.0, accuracy: 0.01)
    }

    func testForwardedZeroPrice() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        XCTAssertNil(StabilityService.reconcileForwarded(
            _: &sc,
            userSats: 500_000,
            totalForwardedSats: 200_000,
            price: 0.0
        ))
    }

    func testForwardedZeroExpected() {
        var sc = testSC(expectedUSD: 0.0, price: 100_000.0, receiverSats: 500_000)
        XCTAssertNil(StabilityService.reconcileForwarded(
            _: &sc,
            userSats: 400_000,
            totalForwardedSats: 500_000,
            price: 100_000.0
        ))
    }

    // MARK: - reconcileIncoming

    func testIncomingRecomputesNative() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_200_000)
        sc.backingSats = 600_000
        StabilityService.reconcileIncoming(&sc)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 1_200_000 - 600_000)
    }

    func testIncomingNoChangeIfStable() {
        var sc = testSC(expectedUSD: 1000.0, price: 100_000.0, receiverSats: 1_000_000)
        StabilityService.reconcileIncoming(&sc)
        XCTAssertEqual(sc.backingSats, 1_000_000)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 0)
    }

    func testIncomingNoBacking() {
        var sc = testSC(expectedUSD: 0.0, price: 100_000.0, receiverSats: 500_000)
        sc.backingSats = 0
        StabilityService.reconcileIncoming(&sc)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 500_000)
    }

    func testIncomingPartialBacking() {
        var sc = testSC(expectedUSD: 300.0, price: 100_000.0, receiverSats: 800_000)
        sc.backingSats = 12345
        StabilityService.reconcileIncoming(&sc)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 800_000 - 12_345)
    }

    // MARK: - applyTrade

    func testTradeBuyReducesStable() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 300.0, price: 100_000.0)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(sc.expectedUSD.amount, 300.0)
        let expectedBacking = UInt64(300.0 / 100_000.0 * 100_000_000.0)
        XCTAssertEqual(sc.backingSats, expectedBacking)
    }

    func testTradeSellIncreasesStable() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 700.0, price: 100_000.0)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(sc.expectedUSD.amount, 700.0)
        let expectedBacking = UInt64(700.0 / 100_000.0 * 100_000_000.0)
        XCTAssertEqual(sc.backingSats, expectedBacking)
    }

    func testTradeToZero() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 0.0, price: 100_000.0)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(sc.expectedUSD.amount, 0.0)
        XCTAssertEqual(sc.backingSats, 0)
    }

    func testTradeZeroPriceSkipsBackingUpdate() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let backingBefore = sc.backingSats
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 700.0, price: 0.0)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(sc.expectedUSD.amount, 700.0)
        XCTAssertEqual(sc.backingSats, backingBefore)
    }

    func testTradeAtDifferentPrice() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 500.0, price: 200_000.0)
        XCTAssertEqual(outcome, .applied)
        let expectedBacking = UInt64(500.0 / 200_000.0 * 100_000_000.0)
        XCTAssertEqual(sc.backingSats, expectedBacking)
        XCTAssertEqual(expectedBacking, 250_000)
    }

    func testTradeFullBalanceToStable() {
        var sc = testSC(expectedUSD: 0.0, price: 100_000.0, receiverSats: 1_000_000)
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 1000.0, price: 100_000.0)
        XCTAssertEqual(outcome, .applied)
        XCTAssertEqual(sc.expectedUSD.amount, 1000.0)
        XCTAssertEqual(sc.backingSats, 1_000_000)
    }

    func testTradeRejectsAboveReceiverBalance() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let oldBacking = sc.backingSats
        let oldExpected = sc.expectedUSD.amount
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 1_500.0, price: 100_000.0)
        XCTAssertEqual(outcome, .rejectedAbovePar)
        XCTAssertEqual(sc.expectedUSD.amount, oldExpected)
        XCTAssertEqual(sc.backingSats, oldBacking)
    }

    func testTradeRejectsDriftLoss() {
        // Receiver has 1_200_000 sats, current backing is 500_000 (500 USD at 100k price).
        // Drift = 700_000 sats. A trade to 400 USD would set backing to 400_000,
        // losing 100_000 of the drift. This must be rejected.
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_200_000)
        let oldBacking = sc.backingSats
        let oldExpected = sc.expectedUSD.amount
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 400.0, price: 100_000.0)
        XCTAssertEqual(outcome, .rejectedDriftLoss)
        XCTAssertEqual(sc.expectedUSD.amount, oldExpected)
        XCTAssertEqual(sc.backingSats, oldBacking)
    }

    func testTinyTradePreservesDrift() {
        // A 1-cent trade on a $500 channel must not zero out the drift
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_500_000)
        StabilityService.applyTrade(&sc, newExpectedUSD: 499.99, price: 100_000.0)
        XCTAssertEqual(sc.backingSats, 499_990)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 1_500_000 - 499_990)
    }

    func testArithmeticUnderflowLeavesStateUnchanged() {
        // Backing 100 sats (tiny expected), receiver 200_000 sats.
        // Trade to 0 USD would go to 0 backing — losing 100 sats of drift.
        var sc = testSC(expectedUSD: 0.0, price: 100_000_0, receiverSats: 200_000)
        sc.backingSats = 100
        sc.expectedUSD = USD(amount: 0.0)
        let oldBacking = sc.backingSats
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 0.0, price: 100_000.0)
        XCTAssertEqual(outcome, .rejectedDriftLoss)
        XCTAssertEqual(sc.backingSats, oldBacking)
    }

    // MARK: - recomputeNative

    func testNativeHalfStableHalfNative() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        StabilityService.recomputeNative(&sc)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 500_000)
    }

    func testNativeFullyStabilized() {
        var sc = testSC(expectedUSD: 1000.0, price: 100_000.0, receiverSats: 1_000_000)
        StabilityService.recomputeNative(&sc)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 0)
    }

    func testNativeBackingExceedsReceiverSaturates() {
        var sc = testSC(expectedUSD: 1000.0, price: 100_000.0, receiverSats: 800_000)
        StabilityService.recomputeNative(&sc)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 0)
    }

    func testNativeUpdatedAfterReconcileIncoming() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_200_000)
        sc.backingSats = 600_000
        StabilityService.reconcileIncoming(&sc)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 1_200_000 - 600_000)
    }

    func testNativeUpdatedAfterApplyTrade() {
        var sc = testSC(expectedUSD: 500.0, price: 100_000.0, receiverSats: 1_000_000)
        let outcome = StabilityService.applyTrade(&sc, newExpectedUSD: 800.0, price: 100_000.0)
        XCTAssertEqual(outcome, .applied)
        let expectedBacking = UInt64(800.0 / 100_000.0 * 100_000_000.0)
        XCTAssertEqual(sc.nativeChannelBTC.sats, 1_000_000 - expectedBacking)
    }

    func testNativeUpdatedAfterReconcileOutgoing() {
        var sc = testSC(expectedUSD: 1000.0, price: 100_000.0, receiverSats: 900_000)
        _ = StabilityService.reconcileOutgoing(&sc, price: 100_000.0)
        XCTAssertLessThanOrEqual(sc.nativeChannelBTC.sats, 1)
    }

    // MARK: - Bitcoin / USD

    func testBitcoinFromSats() {
        let btc = Bitcoin.fromSats(100_000_000)
        XCTAssertEqual(btc.toBTC(), 1.0)
    }

    func testBitcoinFromBTC() {
        let btc = Bitcoin.fromBTC(1.5)
        XCTAssertEqual(btc.sats, 150_000_000)
    }

    func testBitcoinFromUSD() {
        let usd = USD(amount: 100_000.0)
        let btc = Bitcoin.fromUSD(usd, price: 100_000.0)
        XCTAssertEqual(btc.sats, 100_000_000)
    }

    func testUSDFromBitcoin() {
        let btc = Bitcoin.fromBTC(1.0)
        let usd = USD.fromBitcoin(btc, price: 50_000.0)
        XCTAssertEqual(usd.amount, 50_000.0)
    }

    func testUSDToMsats() {
        let usd = USD(amount: 100.0)
        let msats = usd.toMsats(price: 100_000.0)
        XCTAssertEqual(msats, 100_000_000)
    }

    // MARK: - Stability Check Action

    func testStabilityActionStable() {
        let sc = testSC(expectedUSD: 100.0, price: 100_000.0, receiverSats: 100_000)
        let result = StabilityService.checkStabilityAction(sc, price: 100_000.0)
        XCTAssertEqual(result.action, .stable)
    }

    // MARK: - tradeBackingAfterDelta & Drift Preservation

    func testTradeBackingAfterDeltaPreservesDrift() {
        let backing = StabilityService.tradeBackingAfterDelta(
            receiverSats: 20_000,
            currentBackingSats: 10_300,
            currentExpectedUSD: 10.0,
            newExpectedUSD: 20.0,
            price: 100_000.0
        )
        XCTAssertEqual(backing, 20_300)
    }

    func testTradeBackingAfterDeltaSubCentExit() {
        let backing = StabilityService.tradeBackingAfterDelta(
            receiverSats: 10_000,
            currentBackingSats: 500,
            currentExpectedUSD: 1.0,
            newExpectedUSD: 0.005,
            price: 100_000.0
        )
        XCTAssertEqual(backing, 0)
    }
}
