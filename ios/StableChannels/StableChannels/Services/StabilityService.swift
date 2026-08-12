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
        if price > 0.0 {
            sc.latestPrice = price
        }

        sc.onchainBTC = Bitcoin(sats: onchainBalanceSats)
        sc.onchainUSD = USD.fromBitcoin(sc.onchainBTC, price: sc.latestPrice)

        let matchingChannel: ChannelDetails?
        if sc.userChannelId.isEmpty {
            matchingChannel = channels.first
        } else {
            matchingChannel = channels.first { $0.userChannelId == sc.userChannelId }
        }

        guard let channel = matchingChannel else { return false }

        if sc.userChannelId.isEmpty {
            sc.userChannelId = channel.userChannelId
            sc.channelId = channel.channelId
        }
        sc.channelId = channel.channelId
        sc.counterparty = channel.counterpartyNodeId

        guard channel.isChannelReady else { return true }

        let unspendablePunishmentSats = channel.unspendablePunishmentReserve ?? 0
        let ourBalanceSats = (channel.outboundCapacityMsat / 1000) + unspendablePunishmentSats
        let theirBalanceSats = channel.channelValueSats > ourBalanceSats
            ? channel.channelValueSats - ourBalanceSats : 0

        if sc.isStableReceiver {
            sc.stableReceiverBTC = Bitcoin(sats: ourBalanceSats)
            sc.stableProviderBTC = Bitcoin(sats: theirBalanceSats)
        } else {
            sc.stableProviderBTC = Bitcoin(sats: ourBalanceSats)
            sc.stableReceiverBTC = Bitcoin(sats: theirBalanceSats)
        }

        sc.stableReceiverUSD = USD.fromBitcoin(sc.stableReceiverBTC, price: sc.latestPrice)
        sc.stableProviderUSD = USD.fromBitcoin(sc.stableProviderBTC, price: sc.latestPrice)

        recomputeNative(&sc)

        return true
    }
}
