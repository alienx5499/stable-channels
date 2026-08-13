import Foundation

/// Constructs and cryptographically signs stability payment envelopes for peer node TLV wire messaging.
enum StabilityEnvelopeBuilder {
    static func generateSettlementId() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func buildSignedStabilityEnvelope(
        settlementId: String,
        channelId: String,
        amountMsat: UInt64,
        direction: String,
        expectedUsd: Double,
        createdAt: UInt64,
        expiresAt: UInt64,
        signer: ([UInt8]) throws -> String
    ) throws -> Data {
        let payload: [String: Any] = [
            "type": Constants.stabilityPaymentMessageType,
            "settlement_id": settlementId,
            "channel_id": channelId.lowercased(),
            "amount_msat": amountMsat,
            "direction": direction,
            "expected_usd": expectedUsd,
            "created_at": createdAt,
            "expires_at": expiresAt
        ]

        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadStr = String(data: payloadData, encoding: .utf8) else {
            throw NSError(
                domain: "StableChannels",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to serialize payload"]
            )
        }

        let signature = try signer(Array(payloadStr.utf8))

        let envelope: [String: Any] = [
            "payload": payloadStr,
            "signature": signature
        ]

        guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelope),
              let envelopeStr = String(data: envelopeData, encoding: .utf8) else {
            throw NSError(
                domain: "StableChannels",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to serialize envelope"]
            )
        }

        return Data(envelopeStr.utf8)
    }
}
