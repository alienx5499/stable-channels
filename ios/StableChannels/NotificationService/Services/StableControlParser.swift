import Foundation
import UserNotifications
import LDKNode

enum StableControlResult {
    case none
    case handled
    case deferToForeground
}

enum StableControlParser {
    static func handleStableControl(
        node: LDKNode.Node,
        db: PaymentDatabase,
        priceFetcher: PriceFetcher,
        customRecords: [CustomTlvRecord]
    ) -> StableControlResult {
        for record in customRecords where record.typeNum == Constants.stableChannelTLVType {
            if record.value == Data([1]) {
                continue
            }
            guard let envelopeStr = String(data: record.value, encoding: .utf8),
                  let envelopeData = envelopeStr.data(using: .utf8),
                  let envelope = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
                  let payloadStr = envelope["payload"] as? String,
                  let signature = envelope["signature"] as? String,
                  node.verifySignature(
                      msg: Array(payloadStr.utf8),
                      sig: signature,
                      pkey: Constants.lspPubkey
                  ),
                  let payloadData = payloadStr.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                  let type = payload["type"] as? String,
                  type == Constants.syncMessageType,
                  let expectedUSD = payload["expected_usd"] as? Double else {
                return .deferToForeground
            }

            // Validate channel_id if present in signed payload
            let channelId = payload["channel_id"] as? String ?? ""
            let channelState = db.readChannelState()
            if let wsChannelId = channelState?.channelId, !channelId.isEmpty,
               channelId.lowercased() != wsChannelId.lowercased() {
                return .deferToForeground
            }

            // Log sync_version for replay-protection audit trail
            if let syncVersion = payload["sync_version"] as? UInt64, syncVersion > 0 {
                NotificationServiceLogger.shared
                    .log("SYNC_V1_VERSION sync_version=\(syncVersion) backing=\(payload["backing_sats"] ?? "nil")")
            }

            let ucid = payload["user_channel_id"] as? String
            return db
                .applySyncMessage(expectedUSD: expectedUSD, payloadUserChannelId: ucid, priceFetcher: priceFetcher) ?
                .handled : .deferToForeground
        }
        return .none
    }

    static func isStabilityPayment(_ customRecords: [CustomTlvRecord]) -> Bool {
        customRecords.contains { $0.typeNum == Constants.stableChannelTLVType && $0.value == Data([1]) }
    }
}
