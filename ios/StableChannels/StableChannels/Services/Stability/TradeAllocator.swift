import Foundation

/// Handles trade delta calculations and backing allocation state transitions.
enum TradeAllocator {
    enum TradeOutcome {
        case applied
        case rejectedDriftLoss
        case rejectedAbovePar
    }

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
            let actionable = StabilityChecker.allocationDriftIsActionable(
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
        StabilityReconciler.recomputeNative(&sc)

        return .applied
    }
}
