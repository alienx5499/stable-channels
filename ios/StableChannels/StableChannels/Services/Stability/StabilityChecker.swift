import Foundation
import LDKNode

/// Evaluates stability status and determines required rebalancing actions.
enum StabilityChecker {
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
}
