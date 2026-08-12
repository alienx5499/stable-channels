import Foundation

/// Handles position reconciliation when payments or forwards occur.
enum StabilityReconciler {
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
        recomputeNative(&sc)

        return usdToDeduct
    }

    /// Reconcile an incoming payment - backingSats stays the same, native absorbs the increase.
    static func reconcileIncoming(_ sc: inout StableChannel) {
        recomputeNative(&sc)
    }

    /// Recompute native BTC from receiver sats and backing sats.
    static func recomputeNative(_ sc: inout StableChannel) {
        let nativeSats = sc.stableReceiverBTC.sats >= sc.backingSats
            ? sc.stableReceiverBTC.sats - sc.backingSats
            : 0
        sc.nativeSats = nativeSats
        sc.nativeChannelBTC = Bitcoin(sats: nativeSats)
    }
}
