import Foundation

/// Pure domain calculations for amount inputs, unit conversions, and balance percentages.
enum SendAmountCalculator {
    static func normalizeInput(_ text: String, unit: SendAmountUnit) -> String {
        guard !text.isEmpty else { return "" }
        switch unit {
        case .usd:
            guard let val = Double(text), val > 0 else { return "" }
            return String(format: "%.2f", val)
        case .sats:
            guard let sats = UInt64(text), sats > 0 else { return "" }
            return "\(sats)"
        case .btc:
            guard let btc = Double(text), btc > 0 else { return "" }
            var trimmed = String(format: "%.8f", btc)
            while trimmed.hasSuffix("0") && trimmed.contains(".") {
                trimmed.removeLast()
            }
            if trimmed.hasSuffix(".") { trimmed.removeLast() }
            return trimmed
        }
    }

    static func computeEffectiveSats(
        destination: SendDestination?,
        inputText: String,
        unit: SendAmountUnit,
        btcPrice: Double
    ) -> UInt64 {
        if let dest = destination, case .bolt11(_, _, let msat) = dest, let msat, msat > 0 {
            return msat / 1000
        }
        guard let val = Double(inputText), val > 0 else { return 0 }
        switch unit {
        case .sats:
            return (val.isFinite && val >= 1 && val < Double(UInt64.max)) ? UInt64(val) : 0
        case .usd:
            guard btcPrice > 0 else { return 0 }
            let sats = (val / btcPrice) * Double(Constants.satsInBTC)
            return (sats.isFinite && sats >= 1 && sats < Double(UInt64.max)) ? UInt64(sats) : 0
        case .btc:
            let sats = val * Double(Constants.satsInBTC)
            return (sats.isFinite && sats >= 0.5 && sats < Double(UInt64.max)) ? UInt64(round(sats)) : 0
        }
    }

    static func formatSatsForUnit(_ sats: UInt64, unit: SendAmountUnit, btcPrice: Double) -> String {
        guard sats > 0 else { return "" }
        switch unit {
        case .usd:
            guard btcPrice > 0 else { return "" }
            let usd = (Double(sats) / Double(Constants.satsInBTC)) * btcPrice
            return String(format: "%.2f", usd)
        case .sats:
            return "\(sats)"
        case .btc:
            let btc = Double(sats) / Double(Constants.satsInBTC)
            return String(format: "%.8f", btc)
        }
    }

    static func calculatePercentageAmount(
        percent: Int,
        totalBalanceSats: UInt64,
        unit: SendAmountUnit,
        btcPrice: Double
    ) -> String {
        guard totalBalanceSats > 0, btcPrice > 0 else { return "" }
        let targetSats = (totalBalanceSats * UInt64(percent)) / 100
        return formatSatsForUnit(targetSats, unit: unit, btcPrice: btcPrice)
    }
}
