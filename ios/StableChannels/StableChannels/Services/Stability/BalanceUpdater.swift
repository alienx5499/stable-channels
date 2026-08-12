import Foundation
import LDKNode

/// Updates balances across StableChannel, Lightning, and Onchain states.
enum BalanceUpdater {
    /// Update balances across channels, onchain wallet, and price feed.
    @discardableResult
    static func updateBalances(
        sc: inout StableChannel,
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

        StabilityReconciler.recomputeNative(&sc)

        return true
    }
}
