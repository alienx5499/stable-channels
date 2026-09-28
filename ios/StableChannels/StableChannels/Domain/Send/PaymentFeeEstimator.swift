import Foundation

/// Pure calculations for Lightning routing and onchain network fee estimates.
enum PaymentFeeEstimator {
    /// Estimates the expected Lightning fee for forwarding an amount across the LSP or channel peer.
    static func estimateLightningFee(
        sats: UInt64,
        baseMsat: UInt64,
        proportionalMillionths: UInt64
    ) -> UInt64 {
        guard sats > 0 else { return 0 }
        let amountMsat = saturatingMultiply(sats, 1_000)
        let proportionalMsat = saturatingMultiply(amountMsat, proportionalMillionths) / 1_000_000
        let feeMsat = saturatingAdd(baseMsat, proportionalMsat)
        return saturatingAdd(feeMsat, 999) / 1_000
    }

    /// Estimates the expected onchain transaction fee based on fee rate and send type.
    static func estimateOnchainFee(
        feeRateSatVb: UInt64,
        isSendAll: Bool,
        sendVBytes: UInt64 = 140,
        sendAllVBytes: UInt64 = 110
    ) -> UInt64 {
        let vbytes = isSendAll ? sendAllVBytes : sendVBytes
        return saturatingMultiply(feeRateSatVb, vbytes)
    }

    // MARK: - Overflow-Safe Arithmetic

    static func saturatingMultiply(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.multipliedReportingOverflow(by: rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }

    static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let result = lhs.addingReportingOverflow(rhs)
        return result.overflow ? UInt64.max : result.partialValue
    }
}

/// Speed and confirmation target tiers for onchain Bitcoin network transactions.
enum NetworkFeeSpeedTier: String, CaseIterable, Identifiable, Sendable {
    case economy
    case standard
    case priority

    var id: String { rawValue }

    var title: String {
        switch self {
        case .economy: return "Economy"
        case .standard: return "Standard"
        case .priority: return "Priority"
        }
    }

    /// Estimated confirmation timeframe description.
    var estimatedTime: String {
        switch self {
        case .economy: return "> 1 hour"
        case .standard: return "≈ 30–60 min"
        case .priority: return "≈ 10–20 min"
        }
    }

    /// Target block depth in the blockchain.
    var targetBlocks: String {
        switch self {
        case .economy: return "12+ blocks"
        case .standard: return "3–6 blocks"
        case .priority: return "1–2 blocks"
        }
    }

    /// Computes the effective fee rate in satoshis per virtual byte (sat/vB).
    func effectiveRate(baseRate: UInt64) -> UInt64 {
        let normalized = max(1, baseRate)
        switch self {
        case .economy:
            let reduced = (normalized * 7) / 10
            return max(1, reduced)
        case .standard:
            return normalized
        case .priority:
            let boosted = (normalized * 14) / 10
            return max(normalized + 1, boosted)
        }
    }
}
