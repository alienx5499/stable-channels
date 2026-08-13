import Foundation
import UserNotifications
import LDKNode

/// Handler for "incoming_payment" direction - wake node to receive pending payments
final class IncomingPaymentHandler: PaymentHandler {
    var direction: PaymentDirection { .incomingPayment }

    func handle(
        node: LDKNode.Node,
        db: PaymentDatabase,
        priceFetcher: PriceFetcher,
        baseContent: UNMutableNotificationContent,
        mutator: NotificationContentMutator,
        completion: @escaping (UNMutableNotificationContent, Bool?) -> Void
    ) {
        let startTime = Date()
        let timeout: TimeInterval = 22
        var received = false
        var persistenceFailed = false
        var handledStableControl = false
        var deferStableControlToForeground = false
        var totalMsat: UInt64 = 0
        var price = 0.0

        eventLoop: while Date().timeIntervalSince(startTime) < timeout {
            guard let event = node.nextEvent() else {
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            switch event {
            case .paymentReceived(let paymentId, let paymentHash, let amountMsat, let customRecords):
                if price <= 0 {
                    price = priceFetcher.fetchPrice()
                }
                let payId = paymentId.map { "\($0)" } ?? "\(paymentHash)"

                if let signedRecord = customRecords.first(where: { $0.typeNum == Constants.signedStabilityTLVType }) {
                    let result = handleSignedStabilityPayment(
                        node: node,
                        db: db,
                        record: signedRecord,
                        amountMsat: amountMsat,
                        paymentHashStr: payId,
                        price: price
                    )
                    if result == .inserted {
                        try? node.eventHandled()
                        received = true
                        totalMsat += amountMsat
                        handledStableControl = true
                        break eventLoop
                    } else if result == .duplicate {
                        try? node.eventHandled()
                        handledStableControl = true
                        break eventLoop
                    }
                }

                let stableControl = StableControlParser.handleStableControl(
                    node: node,
                    db: db,
                    priceFetcher: priceFetcher,
                    customRecords: customRecords
                )
                switch stableControl {
                case .handled:
                    try? node.eventHandled()
                    handledStableControl = true
                    deferStableControlToForeground = false
                    break eventLoop
                case .deferToForeground:
                    deferStableControlToForeground = true
                    handledStableControl = false
                    break eventLoop
                case .none: break
                }

                guard amountMsat >= 1000 else {
                    try? node.eventHandled()
                    break
                }

                // Treat legacy markers as normal lightning under the new security model
                let result = db.recordPayment(
                    paymentId: payId,
                    paymentType: "lightning",
                    direction: "received",
                    amountMsat: amountMsat,
                    amountUSD: self.calculateUSD(amountMsat / 1000, price: price),
                    btcPrice: price,
                    backingDeltaSats: nil,
                    userChannelId: nil
                )
                switch result {
                case .inserted, .duplicate:
                    try? node.eventHandled()
                    totalMsat += amountMsat
                    received = true
                case .failed, .missingChannelRow:
                    persistenceFailed = true
                }
            default:
                try? node.eventHandled()
            }
            if persistenceFailed {
                break eventLoop
            }
        }

        self.finishHandling(
            received: received,
            handledStableControl: handledStableControl,
            deferStableControlToForeground: deferStableControlToForeground,
            persistenceFailed: persistenceFailed,
            totalMsat: totalMsat,
            price: price,
            baseContent: baseContent,
            mutator: mutator,
            completion: completion
        )
    }

    private func finishHandling(
        received: Bool,
        handledStableControl: Bool,
        deferStableControlToForeground: Bool,
        persistenceFailed: Bool,
        totalMsat: UInt64,
        price: Double,
        baseContent: UNMutableNotificationContent,
        mutator: NotificationContentMutator,
        completion: @escaping (UNMutableNotificationContent, Bool?) -> Void
    ) {
        var content: UNMutableNotificationContent
        var shouldPersist: Bool? = nil

        if deferStableControlToForeground {
            content = mutator.buildPending(
                base: baseContent,
                title: "Payment Pending",
                body: "Open app to sync stable position"
            )
            shouldPersist = true
        } else if handledStableControl {
            content = mutator.buildEmpty(base: baseContent)
            shouldPersist = false
        } else if !received && persistenceFailed {
            content = mutator.buildPending(
                base: baseContent,
                title: "Payment Pending",
                body: "Open app to finish recording your payment"
            )
            shouldPersist = true
        } else if !received {
            content = mutator.buildEmpty(base: baseContent)
            shouldPersist = nil
        } else {
            let totalSats = totalMsat / 1000
            let usd = Double(totalSats) / 100_000_000.0 * price
            content = mutator.buildForReceived(base: baseContent, amountSats: totalSats, usd: usd, btcPrice: price)
            shouldPersist = false
        }

        completion(content, shouldPersist)
    }

    private func calculateUSD(_ sats: UInt64, price: Double) -> Double {
        Double(sats) / 100_000_000.0 * price
    }

    private func handleSignedStabilityPayment(
        node: LDKNode.Node,
        db: PaymentDatabase,
        record: CustomTlvRecord,
        amountMsat: UInt64,
        paymentHashStr: String,
        price: Double
    ) -> PaymentInsertResult {
        guard record.value.count <= 8192 else {
            return .failed
        }

        guard let raw = String(data: record.value, encoding: .utf8) else {
            return .failed
        }

        guard let envelopeData = raw.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let payloadStr = envelope["payload"] as? String,
              let signature = envelope["signature"] as? String else {
            return .failed
        }

        guard let payloadData = payloadStr.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let kind = payload["type"] as? String,
              kind == Constants.stabilityPaymentMessageType,
              let settlementId = payload["settlement_id"] as? String,
              let channelId = payload["channel_id"] as? String,
              let signedAmountMsat = payload["amount_msat"] as? UInt64 ?? (payload["amount_msat"] as? NSNumber)?
              .uint64Value,
              let directionStr = payload["direction"] as? String,
              let expectedUsd = payload["expected_usd"] as? Double,
              let createdAt = payload["created_at"] as? UInt64 ?? (payload["created_at"] as? NSNumber)?.uint64Value,
              let expiresAt = payload["expires_at"] as? UInt64 ?? (payload["expires_at"] as? NSNumber)?.uint64Value
        else {
            return .failed
        }

        let isLowerHex32 = { (s: String) -> Bool in
            return s.count == 64 && s.allSatisfy { $0.isNumber || ("a"..."f").contains($0) }
        }

        guard isLowerHex32(settlementId),
              isLowerHex32(channelId),
              signedAmountMsat > 0,
              signedAmountMsat % 1000 == 0,
              expectedUsd >= 0,
              createdAt <= expiresAt,
              expiresAt - createdAt <= UInt64(Constants.stabilityPaymentAuthTTLSecs) else {
            return .failed
        }

        guard let registration = db.registerInboundStabilitySettlement(
            settlementId: settlementId,
            paymentId: paymentHashStr,
            channelId: channelId,
            amountMsat: signedAmountMsat,
            direction: directionStr,
            envelope: raw
        ) else {
            return .failed
        }

        if registration == .applied {
            return .duplicate
        }
        if registration == .invalid {
            return .failed
        }

        let invalidate = { (reason: String) in
            _ = db.finishInboundStabilitySettlement(settlementId: settlementId, state: "invalid", reason: reason)
        }

        guard directionStr == "lsp_to_user" else {
            invalidate("direction")
            return .failed
        }

        guard signedAmountMsat == amountMsat else {
            invalidate("amount")
            return .failed
        }

        guard let receivedAt = db.inboundStabilitySettlementReceivedAt(settlementId: settlementId) else {
            return .failed
        }

        let skew = UInt64(Constants.stabilityPaymentClockSkewSecs)
        let fresh = createdAt <= receivedAt + skew && receivedAt <= expiresAt + skew
        guard fresh else {
            invalidate("expired")
            return .failed
        }

        guard let channelState = db.readChannelState() else {
            return .failed
        }

        let walletChannelId = channelState.channelId
        guard channelId.lowercased() == walletChannelId.lowercased() else {
            invalidate("channel")
            return .failed
        }

        let signatureValid = node.verifySignature(
            msg: Array("stablechannels-stability-payment-v1\n\(payloadStr)".utf8),
            sig: signature,
            pkey: Constants.lspPubkey
        )
        guard signatureValid else {
            invalidate("signature")
            return .failed
        }

        guard price > 0 else {
            return .failed
        }

        let amountSats = amountMsat / 1000
        let backingBefore = channelState.backingSats
        let liveReceiverSats = channelState.receiverSats

        let equilibrium = UInt64((channelState.expectedUSD / price * Double(Constants.satsInBTC)).rounded(.down))
        let backingCap = min(equilibrium, liveReceiverSats)
        let backingAfter: UInt64
        if backingBefore >= backingCap {
            backingAfter = backingBefore
        } else {
            backingAfter = min(backingBefore + amountSats, backingCap)
        }
        let nativeAfter = liveReceiverSats >= backingAfter ? (liveReceiverSats - backingAfter) : 0

        let amountUSD = (Double(amountSats) / Double(Constants.satsInBTC)) * price

        return db.recordSignedStabilityPaymentAndUpdateAllocation(
            paymentId: paymentHashStr,
            settlementId: settlementId,
            amountMsat: amountMsat,
            amountUSD: amountUSD,
            btcPrice: price,
            userChannelId: channelState.userChannelId,
            backingSatsBefore: backingBefore,
            backingSatsAfter: backingAfter,
            nativeSatsAfter: nativeAfter
        )
    }
}
