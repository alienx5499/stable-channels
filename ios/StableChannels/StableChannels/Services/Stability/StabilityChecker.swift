import Foundation
import LDKNode

/// Evaluates stability status and determines required rebalancing actions.
enum StabilityChecker {
    enum StabilityAction: String {
        case stable = "STABLE"
        case pay = "PAY"
        case receive = "RECEIVE"
    }

    struct StabilityResult {
        let action: StabilityAction
        let amountUSD: Double
        let amountSats: UInt64
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

    /// Primary stability check function.
    static func checkStabilityAction(_ sc: StableChannel, price: Double) -> StabilityResult {
        guard sc.isStableReceiver, sc.expectedUSD.amount > 0, price > 0 else {
            return StabilityResult(action: .stable, amountUSD: 0, amountSats: 0)
        }

        let receiverSats = sc.stableReceiverBTC.sats
        let effectiveBacking = sc.backingSats > 0
            ? min(sc.backingSats, receiverSats)
            : UInt64((sc.expectedUSD.amount / price * Double(Constants.satsInBTC)).rounded(.down)).min(receiverSats)

        let currentBackingUSD = Double(effectiveBacking) / Double(Constants.satsInBTC) * price
        let diffUSD = currentBackingUSD - sc.expectedUSD.amount
        let absDiffUSD = abs(diffUSD)
        let percentDiff = (absDiffUSD / sc.expectedUSD.amount) * 100.0

        if absDiffUSD >= Constants.stabilityThresholdUSD, percentDiff >= Constants.stabilityThresholdPercent {
            let diffSats = UInt64((absDiffUSD / price * Double(Constants.satsInBTC)).rounded(.down))
            if diffUSD > 0 {
                return StabilityResult(action: .pay, amountUSD: absDiffUSD, amountSats: diffSats)
            } else {
                return StabilityResult(action: .receive, amountUSD: absDiffUSD, amountSats: diffSats)
            }
        }

        return StabilityResult(action: .stable, amountUSD: 0, amountSats: 0)
    }

    /// Evaluate channels to check if any stability action is required.
    static func checkChannels(
        channels: [ChannelDetails],
        sc: inout StableChannel,
        price: Double
    ) -> (action: StabilityAction, amountUSD: Double, amountSats: UInt64) {
        guard !channels.isEmpty else {
            return (.stable, 0, 0)
        }

        let matchingChannel: ChannelDetails?
        if !sc.userChannelId.isEmpty {
            matchingChannel = channels.first { $0.userChannelId == sc.userChannelId }
        } else {
            matchingChannel = channels.first
        }

        guard let channel = matchingChannel else {
            return (.stable, 0, 0)
        }

        let totalSats = channel.outboundCapacityMsat / 1000
        sc.stableReceiverBTC = Bitcoin(sats: totalSats)
        sc.stableReceiverUSD = USD.fromBitcoin(sc.stableReceiverBTC, price: price)
        sc.latestPrice = price

        StabilityReconciler.recomputeNative(&sc)

        let result = checkStabilityAction(sc, price: price)
        return (result.action, result.amountUSD, result.amountSats)
    }
}
