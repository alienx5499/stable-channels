import Foundation
import LDKNode

/// StabilityService serves as a facade delegating to focused domain services:
/// - `StabilityReconciler`: payment & forward position reconciliation
/// - `TradeAllocator`: trade target deltas & backing allocation
/// - `StabilityChecker`: drift evaluation & stability actions
/// - `BalanceUpdater`: balance calculations across LDK channels and on-chain
enum StabilityService {
    typealias TradeOutcome = TradeAllocator.TradeOutcome
    typealias StabilityAction = StabilityChecker.StabilityAction
    typealias StabilityCheckResult = StabilityChecker.StabilityCheckResult

    // MARK: - Reconciliation Delegation

    static func reconcileOutgoing(_ sc: inout StableChannel, price: Double) -> Double? {
        if let deductedSats = StabilityReconciler.reconcileOutgoing(&sc, price: price) {
            return Double(deductedSats) / Double(Constants.satsInBTC) * price
        }
        return nil
    }

    static func reconcileForwarded(
        _ sc: inout StableChannel,
        userSats _: UInt64,
        totalForwardedSats _: UInt64,
        price: Double
    ) -> Double? {
        StabilityReconciler.reconcileForwarded(&sc, price: price)
        return nil
    }

    static func deductOutgoing(_ sc: inout StableChannel, amountSats: UInt64, price: Double) -> Double? {
        StabilityReconciler.deductOutgoing(
            &sc,
            amountUSD: Double(amountSats) / Double(Constants.satsInBTC) * price,
            price: price
        )
        return nil
    }

    static func recomputeNative(_ sc: inout StableChannel) {
        StabilityReconciler.recomputeNative(&sc)
    }

    static func reconcileIncoming(_ sc: inout StableChannel) {
        StabilityReconciler.reconcileIncoming(&sc)
    }

    // MARK: - Trade Allocation Delegation

    static func normalizeTradeExpectedUSD(_ expectedUSD: Double) -> Double {
        TradeAllocator.normalizeTradeExpectedUSD(expectedUSD)
    }

    static func normalizeBackingSats(
        receiverSats: UInt64,
        backingSats: UInt64,
        expectedUSD: Double,
        price: Double
    ) -> UInt64 {
        TradeAllocator.normalizeBackingSats(
            receiverSats: receiverSats,
            backingSats: backingSats,
            expectedUSD: expectedUSD,
            price: price
        )
    }

    static func allocationDriftIsActionable(
        backingSats: UInt64,
        expectedUSD: Double,
        price: Double
    ) -> Bool {
        StabilityChecker.allocationDriftIsActionable(
            backingSats: backingSats,
            expectedUSD: expectedUSD,
            price: price
        )
    }

    static func tradeBackingAfterDelta(
        receiverSats: UInt64,
        currentBackingSats: UInt64,
        currentExpectedUSD: Double,
        newExpectedUSD: Double,
        price: Double
    ) -> UInt64? {
        TradeAllocator.tradeBackingAfterDelta(
            receiverSats: receiverSats,
            currentBackingSats: currentBackingSats,
            currentExpectedUSD: currentExpectedUSD,
            newExpectedUSD: newExpectedUSD,
            price: price
        )
    }

    static func applyTrade(_ sc: inout StableChannel, newExpectedUSD: Double, price: Double) -> TradeOutcome {
        TradeAllocator.applyTrade(&sc, newExpectedUSD: newExpectedUSD, price: price)
    }

    // MARK: - Stability Check Delegation

    static func checkStabilityAction(_ sc: StableChannel, price: Double) -> StabilityCheckResult {
        StabilityChecker.checkStabilityAction(sc, price: price)
    }

    // MARK: - Balance Update Delegation

    @discardableResult
    static func updateBalances(
        _ sc: inout StableChannel,
        channels: [ChannelDetails],
        onchainBalanceSats: UInt64,
        price: Double
    ) -> Bool {
        BalanceUpdater.updateBalances(sc: &sc, channels: channels, onchainBalanceSats: onchainBalanceSats, price: price)
    }
}
