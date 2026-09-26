import Foundation

/// Active step in the sequential Send workflow.
enum SendFlowStep: Equatable, Sendable {
    case recipient
    case amount
    case confirm
    case success
}

/// Currency unit options for amount entry in the Send workflow.
enum SendAmountUnit: String, CaseIterable, Identifiable, Sendable {
    case usd = "USD"
    case sats = "Sats"
    case btc = "BTC"

    var id: String { rawValue }

    var title: String { rawValue }

    var menuTitle: String {
        switch self {
        case .usd: return "US Dollar (USD)"
        case .sats: return "Satoshis (sats)"
        case .btc: return "Bitcoin (BTC)"
        }
    }

    var symbolOrSuffix: String {
        switch self {
        case .usd: return "$"
        case .sats: return "sats"
        case .btc: return "BTC"
        }
    }

    var placeholder: String {
        switch self {
        case .usd: return "0.00"
        case .sats: return "0"
        case .btc: return "0.00000000"
        }
    }

    var maxDecimals: Int {
        switch self {
        case .usd: return 2
        case .sats: return 0
        case .btc: return 8
        }
    }

    func secondaryConversionText(sats: UInt64, btcPrice: Double) -> String {
        let usd = (Double(sats) / Double(Constants.satsInBTC)) * btcPrice
        switch self {
        case .usd:
            return "≈ \(sats.btcSpacedFormatted) BTC (\(sats) sats)"
        case .sats:
            return "≈ \(usd.usdFormatted) USD (\(sats.btcSpacedFormatted) BTC)"
        case .btc:
            return "≈ \(usd.usdFormatted) USD (\(sats) sats)"
        }
    }

    func allowedRangeText(params: LNURLPayParams, btcPrice: Double) -> String {
        switch self {
        case .usd:
            let minUSD = (Double(params.minSats) / Double(Constants.satsInBTC)) * btcPrice
            let maxUSD = (Double(params.maxSats) / Double(Constants.satsInBTC)) * btcPrice
            return "Allowed: \(minUSD.usdFormatted) – \(maxUSD.usdFormatted) (\(params.minSats)–\(params.maxSats) sats)"
        case .sats:
            return "Allowed range: \(params.minSats) – \(params.maxSats) sats"
        case .btc:
            return "Allowed: \(params.minSats.btcFormatted) – \(params.maxSats.btcFormatted)"
        }
    }
}
