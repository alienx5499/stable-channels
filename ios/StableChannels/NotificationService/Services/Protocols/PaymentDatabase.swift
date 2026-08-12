import Foundation
import LDKNode

/// Protocol for payment database operations
protocol PaymentDatabase {
    func recordPayment(
        paymentId: String,
        paymentType: String,
        direction: String,
        amountMsat: UInt64,
        amountUSD: Double,
        btcPrice: Double,
        backingDeltaSats: Int64?,
        userChannelId: String?
    ) -> PaymentInsertResult

    func paymentExists(paymentId: String) -> Bool
    func readChannelState() -> ChannelState?
    func activeUserChannelId() -> String?
    func applySyncMessage(
        expectedUSD: Double,
        payloadUserChannelId: String?,
        syncVersion: UInt64?,
        price: Double
    ) -> Bool
    func setPendingSendPaymentId(paymentId: String) -> Bool
    func claimPendingSend(amountMsat: UInt64, price: Double) -> Bool
    func loadPendingSend() -> PendingOutgoingStabilityPayment?
    func clearPendingSend()
    func reconcilePendingOutgoingPayment(node: LDKNode.Node) -> Bool

    func registerInboundStabilitySettlement(
        settlementId: String,
        paymentId: String,
        channelId: String,
        amountMsat: UInt64,
        direction: String,
        envelope: String
    ) -> InboundStabilityRegistration?

    func finishInboundStabilitySettlement(
        settlementId: String,
        state: String,
        reason: String?
    ) -> Bool

    func inboundStabilitySettlementReceivedAt(settlementId: String) -> UInt64?

    func recordSignedStabilityPaymentAndUpdateAllocation(
        paymentId: String,
        settlementId: String,
        amountMsat: UInt64,
        amountUSD: Double?,
        btcPrice: Double?,
        userChannelId: String,
        backingSatsBefore: UInt64,
        backingSatsAfter: UInt64,
        nativeSatsAfter: UInt64
    ) -> PaymentInsertResult
}

/// Result of recording a payment
enum PaymentInsertResult {
    case inserted
    case duplicate
    case failed
    case missingChannelRow
}

enum InboundStabilityRegistration: String {
    case new
    case pending
    case applied
    case invalid
}

/// Pending outgoing stability payment marker
struct PendingOutgoingStabilityPayment {
    let paymentId: String
    let amountMsat: UInt64
    let btcPrice: Double
    let createdAt: Int64
}

/// Channel state read from DB
struct ChannelState {
    let expectedUSD: Double
    let backingSats: UInt64
    let nativeSats: UInt64
    let receiverSats: UInt64
    let latestPrice: Double
    let userChannelId: String
    let channelId: String
    let syncVersion: UInt64
}
