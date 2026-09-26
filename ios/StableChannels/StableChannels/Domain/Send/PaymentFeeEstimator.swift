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
