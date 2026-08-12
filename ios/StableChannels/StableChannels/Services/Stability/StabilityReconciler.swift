import Foundation

/// Handles position reconciliation when payments or forwards occur.
enum StabilityReconciler {
    /// Reconcile an outgoing payment. Returns deducted sats if stable position was drained.
    static func reconcileOutgoing(_ sc: inout StableChannel, price: Double) -> UInt64? {
        guard sc.isStableReceiver, sc.expectedUSD.amount > 0, price > 0 else { return nil }

        let targetSats = UInt64((sc.expectedUSD.amount / price * Double(Constants.satsInBTC)).rounded(.down))
        let receiverSats = sc.stableReceiverBTC.sats

        guard receiverSats < targetSats else { return nil }

        let deficitSats = targetSats - receiverSats
        let deficitUSD = Double(deficitSats) / Double(Constants.satsInBTC) * price

        var deductedUSD = deficitUSD
        if sc.expectedUSD.amount < deficitUSD {
            deductedUSD = sc.expectedUSD.amount
        }

        sc.expectedUSD = USD(amount: max(sc.expectedUSD.amount - deductedUSD, 0))

        let newTargetSats = UInt64((sc.expectedUSD.amount / price * Double(Constants.satsInBTC)).rounded(.down))
        sc.backingSats = min(newTargetSats, receiverSats)

        let deductedSats = UInt64((deductedUSD / price * Double(Constants.satsInBTC)).rounded(.down))

        recomputeNative(&sc)
        return deductedSats
    }

    /// Reconcile a forwarded payment.
    static func reconcileForwarded(_ sc: inout StableChannel, price: Double) {
        guard sc.isStableReceiver, sc.expectedUSD.amount > 0, price > 0 else { return }

        let targetSats = UInt64((sc.expectedUSD.amount / price * Double(Constants.satsInBTC)).rounded(.down))
        let receiverSats = sc.stableReceiverBTC.sats

        if receiverSats < targetSats {
            let deficitSats = targetSats - receiverSats
            let deficitUSD = Double(deficitSats) / Double(Constants.satsInBTC) * price
            sc.expectedUSD = USD(amount: max(sc.expectedUSD.amount - deficitUSD, 0))
            let newTargetSats = UInt64((sc.expectedUSD.amount / price * Double(Constants.satsInBTC)).rounded(.down))
            sc.backingSats = min(newTargetSats, receiverSats)
        } else {
            sc.backingSats = min(targetSats, receiverSats)
        }

        recomputeNative(&sc)
    }

    /// Deduct a specific USD amount from the expected USD position.
    static func deductOutgoing(_ sc: inout StableChannel, amountUSD: Double, price: Double) {
        guard sc.isStableReceiver, sc.expectedUSD.amount > 0, price > 0 else { return }
        sc.expectedUSD = USD(amount: max(sc.expectedUSD.amount - amountUSD, 0))
        let targetSats = UInt64((sc.expectedUSD.amount / price * Double(Constants.satsInBTC)).rounded(.down))
        sc.backingSats = min(targetSats, sc.stableReceiverBTC.sats)
        recomputeNative(&sc)
    }

    /// Reconcile an incoming payment - backingSats stays the same, native absorbs the increase.
    static func reconcileIncoming(_ sc: inout StableChannel) {
        recomputeNative(&sc)
    }

    /// Recompute native Channel BTC.
    static func recomputeNative(_ sc: inout StableChannel) {
        let receiverSats = sc.stableReceiverBTC.sats
        let backing = sc.backingSats
        let nativeSats = receiverSats >= backing ? receiverSats - backing : 0
        sc.nativeSats = nativeSats
        sc.nativeChannelBTC = Bitcoin(sats: nativeSats)
    }
}
