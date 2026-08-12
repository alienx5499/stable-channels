import Foundation
import LDKNode

/// Updates balances across StableChannel, Lightning, and Onchain states.
enum BalanceUpdater {
    /// Update balances across channels, onchain wallet, and price feed.
    static func updateBalances(
        sc: inout StableChannel,
        channels: [ChannelDetails],
        balances: Balances?,
        price: Double
    ) {
        sc.latestPrice = price

        let activeChannel: ChannelDetails?
        if !sc.userChannelId.isEmpty {
            activeChannel = channels.first { $0.userChannelId == sc.userChannelId }
        } else {
            activeChannel = channels.first
        }

        if let channel = activeChannel {
            let receiverSats = channel.outboundCapacityMsat / 1000
            sc.stableReceiverBTC = Bitcoin(sats: receiverSats)
            sc.stableReceiverUSD = USD.fromBitcoin(sc.stableReceiverBTC, price: price)

            if sc.channelId.isEmpty {
                sc.channelId = channel.channelId
            }
            if sc.userChannelId.isEmpty {
                sc.userChannelId = channel.userChannelId
            }
            if sc.counterparty == Constants.defaultLSPPubkey || sc.counterparty.isEmpty {
                sc.counterparty = channel.counterpartyNodeId
            }

            StabilityReconciler.recomputeNative(&sc)
        } else if channels.isEmpty {
            sc.stableReceiverBTC = .zero
            sc.stableReceiverUSD = .zero
            sc.nativeChannelBTC = .zero
            sc.backingSats = 0
            sc.nativeSats = 0
        }

        if let balances {
            sc.onchainBTC = Bitcoin(sats: balances.totalOnchainBalanceSats)
            sc.onchainUSD = USD.fromBitcoin(sc.onchainBTC, price: price)
        }
    }
}
