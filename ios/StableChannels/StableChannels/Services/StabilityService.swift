import Foundation
import LDKNode

/// Pure stability logic - direct port of src/stable.rs
enum StabilityService {
    // MARK: - Reconciliation

    /// Reconcile an outgoing payment against the stable position.
    /// Returns the USD amount deducted from stable, or nil if fully covered by native BTC.
    static func reconcileOutgoing(_ sc: inout StableChannel, price: Double) -> Double? {
        guard sc.expectedUSD.amount > 0.01, sc.backingSats > 0, price > 0.0 else { return nil }

        let userSats = sc.stableReceiverBTC.sats
        guard sc.backingSats > userSats else { return nil }

        let overflowSats = sc.backingSats - userSats
        let usdToDeduct = Double(overflowSats) / Double(Constants.satsInBTC) * price
        let newExpected = max(sc.expectedUSD.amount - usdToDeduct, 0.0)

        sc.expectedUSD = USD(amount: newExpected)
        let btcAmount = newExpected / price
        sc.backingSats = UInt64(btcAmount * 100_000_000.0)
        sc.nativeSats = sc.stableReceiverBTC.sats >= sc.backingSats
            ? sc.stableReceiverBTC.sats - sc.backingSats : 0
        recomputeNative(&sc)

        return usdToDeduct
    }

    /// Reconcile a forwarded payment on the LSP side.
    /// `userSats` MUST be the balance BEFORE the spend - callers with a post-spend
    /// balance must add totalForwardedSats back first, or stable is over-deducted.
    /// Returns the USD amount deducted from stable, or nil if fully covered by native.
    static func reconcileForwarded(
        _ sc: inout StableChannel,
        userSats: UInt64,
        totalForwardedSats: UInt64,
        price: Double
    ) -> Double? {
        guard sc.expectedUSD.amount > 0.0, price > 0.0 else { return nil }

        let nativeSats = userSats >= sc.backingSats ? userSats - sc.backingSats : 0
        let overflowSats = totalForwardedSats >= nativeSats ? totalForwardedSats - nativeSats : 0

        guard overflowSats > 0 else { return nil }

        let usdToDeduct = Double(overflowSats) / Double(Constants.satsInBTC) * price
        let newExpected = max(sc.expectedUSD.amount - usdToDeduct, 0.0)

        sc.expectedUSD = USD(amount: newExpected)
        if price > 0.0 {
            let btcAmount = newExpected / price
            sc.backingSats = UInt64(btcAmount * 100_000_000.0)
        }
        sc.nativeSats = sc.stableReceiverBTC.sats >= sc.backingSats
            ? sc.stableReceiverBTC.sats - sc.backingSats : 0
        recomputeNative(&sc)

        return usdToDeduct
    }

    /// Pre-deduct stable balance for a known outgoing amount (e.g. splice-out).
    /// Returns the USD amount deducted, or nil if fully covered by native.
    static func deductOutgoing(_ sc: inout StableChannel, amountSats: UInt64, price: Double) -> Double? {
        guard sc.expectedUSD.amount > 0.01, price > 0.0 else { return nil }

        let nativeSats = sc.nativeChannelBTC.sats
        guard amountSats > nativeSats else { return nil }

        let overflowSats = amountSats - nativeSats
        let usdToDeduct = Double(overflowSats) / Double(Constants.satsInBTC) * price
        let newExpected = max(sc.expectedUSD.amount - usdToDeduct, 0.0)

        sc.expectedUSD = USD(amount: newExpected)
        let btcAmount = newExpected / price
        sc.backingSats = UInt64(btcAmount * 100_000_000.0)
        sc.nativeSats = sc.stableReceiverBTC.sats >= sc.backingSats
            ? sc.stableReceiverBTC.sats - sc.backingSats : 0
        recomputeNative(&sc)

        return usdToDeduct
    }

    /// Recompute native BTC from receiver sats and backing sats.
    static func recomputeNative(_ sc: inout StableChannel) {
        let nativeSats = sc.stableReceiverBTC.sats >= sc.backingSats
            ? sc.stableReceiverBTC.sats - sc.backingSats
            : 0
        sc.nativeChannelBTC = Bitcoin(sats: nativeSats)
    }

    /// Reconcile an incoming payment - backingSats stays the same, native absorbs the increase.
    static func reconcileIncoming(_ sc: inout StableChannel) {
        recomputeNative(&sc)
    }

    // MARK: - Trade Delta & Backing Allocation

    /// Treat sub-cent targets as a full exit throughout trade processing.
    static func normalizeTradeExpectedUSD(_ expectedUSD: Double) -> Double {
        if expectedUSD.isFinite && expectedUSD >= 0.0 && expectedUSD < 0.01 {
            return 0.0
        }
        return expectedUSD
    }

    /// Absorb sub-cent native residue into the stable position for full BTC-to-USD trades.
    static func normalizeBackingSats(
        receiverSats: UInt64,
        backingSats: UInt64,
        expectedUSD: Double,
        price: Double
    ) -> UInt64 {
        guard receiverSats > 0,
              backingSats <= receiverSats,
              expectedUSD > 0.0,
              price.isFinite,
              price > 0.0 else {
            return backingSats
        }

        let nativeSats = receiverSats - backingSats
        let nativeUSD = Double(nativeSats) / Double(Constants.satsInBTC) * price
        if nativeUSD < 0.01 {
            return receiverSats
        }
        return backingSats
    }

    /// Determine whether allocation drift exceeds stability payment thresholds.
    static func allocationDriftIsActionable(
        backingSats: UInt64,
        expectedUSD: Double,
        price: Double
    ) -> Bool {
        let currentValue = Double(backingSats) / Double(Constants.satsInBTC) * price
        let driftUSD = abs(currentValue - expectedUSD)
        if expectedUSD < 0.01 {
            return driftUSD >= Constants.stabilityThresholdUSD
        }
        let driftPercent = (driftUSD / expectedUSD) * 100.0
        return driftUSD >= Constants.stabilityThresholdUSD && driftPercent >= Constants.stabilityThresholdPercent
    }

    /// Derive backing sats after applying a trade target delta, preserving existing stability drift.
    /// Direct port of src/stable.rs trade_backing_after_delta()
    static func tradeBackingAfterDelta(
        receiverSats: UInt64,
        currentBackingSats: UInt64,
        currentExpectedUSD: Double,
        newExpectedUSD: Double,
        price: Double
    ) -> UInt64? {
        let normNewExpectedUSD = normalizeTradeExpectedUSD(newExpectedUSD)
        guard currentExpectedUSD.isFinite, currentExpectedUSD >= 0.0,
              normNewExpectedUSD.isFinite, normNewExpectedUSD >= 0.0,
              price.isFinite, price > 0.0 else {
            return nil
        }

        let receiverUSD = Double(receiverSats) / Double(Constants.satsInBTC) * price
        if normNewExpectedUSD > receiverUSD {
            return nil
        }

        if normNewExpectedUSD == 0.0 {
            let actionable = allocationDriftIsActionable(
                backingSats: currentBackingSats,
                expectedUSD: currentExpectedUSD,
                price: price
            )
            return actionable ? nil : 0
        }

        let currentTargetSatsF = currentExpectedUSD / price * Double(Constants.satsInBTC)
        let newTargetSatsF = normNewExpectedUSD / price * Double(Constants.satsInBTC)
        guard currentTargetSatsF.isFinite, newTargetSatsF.isFinite,
              currentTargetSatsF < Double(UInt64.max),
              newTargetSatsF < Double(UInt64.max) else {
            return nil
        }

        let currentTargetSats = UInt64(floor(currentTargetSatsF))
        let newTargetSats = UInt64(floor(newTargetSatsF))

        var backingSats: UInt64
        if normNewExpectedUSD >= currentExpectedUSD {
            let targetDiff = newTargetSats >= currentTargetSats ? newTargetSats - currentTargetSats : 0
            guard let added = currentBackingSats.addingReportingOverflow(targetDiff)
                .overflow ? nil : currentBackingSats + targetDiff else {
                return nil
            }
            backingSats = added
        } else {
            let targetDiff = currentTargetSats >= newTargetSats ? currentTargetSats - newTargetSats : 0
            guard currentBackingSats >= targetDiff else {
                return nil
            }
            backingSats = currentBackingSats - targetDiff
        }

        if currentExpectedUSD < 0.01 && currentBackingSats == 0 {
            backingSats = normalizeBackingSats(
                receiverSats: receiverSats,
                backingSats: backingSats,
                expectedUSD: normNewExpectedUSD,
                price: price
            )
        }

        if backingSats > 0 && backingSats <= receiverSats {
            return backingSats
        }
        return nil
    }

    // MARK: - Trade Outcome

    enum TradeOutcome {
        case applied
        case rejectedDriftLoss
        case rejectedAbovePar
    }

    /// Apply a trade - apply target delta at local price, preserving existing stability drift.
    static func applyTrade(_ sc: inout StableChannel, newExpectedUSD: Double, price: Double) -> TradeOutcome {
        let normNewExpectedUSD = normalizeTradeExpectedUSD(newExpectedUSD)
        let receiverSats = sc.stableReceiverBTC.sats

        if price > 0.0 {
            let receiverValueUSD = Double(receiverSats) / Double(Constants.satsInBTC) * price
            if normNewExpectedUSD > receiverValueUSD {
                return .rejectedAbovePar
            }
        }

        guard let backingSats = tradeBackingAfterDelta(
            receiverSats: receiverSats,
            currentBackingSats: sc.backingSats,
            currentExpectedUSD: sc.expectedUSD.amount,
            newExpectedUSD: normNewExpectedUSD,
            price: price
        ) else {
            return .rejectedDriftLoss
        }

        sc.expectedUSD = USD(amount: normNewExpectedUSD)
        sc.backingSats = backingSats
        sc.nativeSats = receiverSats >= backingSats ? receiverSats - backingSats : 0
        recomputeNative(&sc)

        return .applied
    }

    // MARK: - Stability Check

    enum StabilityAction: String {
        case stable = "STABLE"
        case highRiskNoAction = "HIGH_RISK_NO_ACTION"
        case checkOnly = "CHECK_ONLY"
        case pay = "PAY"
    }

    struct StabilityCheckResult {
        let action: StabilityAction
        let percentFromPar: Double
        let stableUSDValue: Double
        let targetUSD: Double
        let dollarsFromPar: Double
    }

    /// Determine the stability action without sending payment.
    static func checkStabilityAction(_ sc: StableChannel, price: Double) -> StabilityCheckResult {
        let targetUSD = sc.expectedUSD.amount

        // No backing means no stable position - nothing to drift.
        guard sc.backingSats > 0 else {
            return StabilityCheckResult(
                action: .stable,
                percentFromPar: 0.0,
                stableUSDValue: 0.0,
                targetUSD: targetUSD,
                dollarsFromPar: 0.0
            )
        }

        let stableUSDValue = Double(sc.backingSats) / 100_000_000.0 * price

        let dollarsFromPar = stableUSDValue - targetUSD
        let percentFromPar = targetUSD > 0.0 ? abs(dollarsFromPar / targetUSD) * 100.0 : 0.0
        let isReceiverBelowExpected = stableUSDValue < targetUSD

        let action: StabilityAction
        if percentFromPar < Constants.stabilityThresholdPercent
            || abs(dollarsFromPar) < Constants.stabilityThresholdUSD {
            action = .stable
        } else if sc.riskLevel > Constants.maxRiskLevel {
            action = .highRiskNoAction
        } else if (sc.isStableReceiver && isReceiverBelowExpected)
            || (!sc.isStableReceiver && !isReceiverBelowExpected) {
            action = .checkOnly
        } else {
            action = .pay
        }

        return StabilityCheckResult(
            action: action,
            percentFromPar: percentFromPar,
            stableUSDValue: stableUSDValue,
            targetUSD: targetUSD,
            dollarsFromPar: dollarsFromPar
        )
    }

    // MARK: - Balance Update

    /// Update balances on a StableChannel from LDK channel data.
    /// Returns true if a matching channel was found.
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

        // Update on-chain
        sc.onchainBTC = Bitcoin(sats: onchainBalanceSats)
        sc.onchainUSD = USD.fromBitcoin(sc.onchainBTC, price: sc.latestPrice)

        // Find matching channel
        let matchingChannel: ChannelDetails?
        if sc.userChannelId.isEmpty {
            matchingChannel = channels.first
        } else {
            matchingChannel = channels.first { $0.userChannelId == sc.userChannelId }
        }

        guard let channel = matchingChannel else { return false }

        // Auto-assign channel IDs if not set
        if sc.userChannelId.isEmpty {
            sc.userChannelId = channel.userChannelId
            sc.channelId = channel.channelId
        }
        // Always keep channelId & counterparty current
        sc.channelId = channel.channelId
        sc.counterparty = channel.counterpartyNodeId

        // Skip balance update if channel is not ready yet - during ChannelPending,
        // outbound_capacity_msat is 0, which produces a misleading near-zero balance.
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

        // Native BTC is the portion not backing the stable position
        recomputeNative(&sc)

        return true
    }
}
