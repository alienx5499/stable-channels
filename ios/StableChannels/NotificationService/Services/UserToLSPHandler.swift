import Foundation
import UserNotifications
import LDKNode

/// Handler for "user_to_lsp" direction - calculate and send payment to LSP
final class UserToLSPHandler: PaymentHandler {
    var direction: PaymentDirection { .userToLsp }

    func handle(
        node: LDKNode.Node,
        db: PaymentDatabase,
        priceFetcher: PriceFetcher,
        baseContent: UNMutableNotificationContent,
        mutator: NotificationContentMutator,
        completion: @escaping (UNMutableNotificationContent, Bool?) -> Void
    ) {
        // Check pending outgoing
        guard db.reconcilePendingOutgoingPayment(node: node) else {
            completion(
                mutator.buildPending(
                    base: baseContent,
                    title: "Payment Sent",
                    body: "Open app to finish syncing the stability payment"
                ),
                true
            )
            return
        }

        // Cooldown check
        let shared = UserDefaults(suiteName: Constants.appGroup)
        shared?.synchronize()
        let lastSent = shared?.double(forKey: "nse_last_stability_sent") ?? 0
        if lastSent > 0 && Date().timeIntervalSince1970 - lastSent < 120 {
            completion(mutator.buildStablePosition(base: baseContent, body: "Position is stable"), nil)
            return
        }

        // Read channel state
        guard let channelState = db.readChannelState() else {
            completion(
                mutator.buildPending(
                    base: baseContent,
                    title: "Payment Pending",
                    body: "Open app to process stability payment"
                ),
                true
            )
            return
        }

        let backingSats = channelState.backingSats
        guard channelState.expectedUSD >= 0.01 else {
            completion(mutator.buildStablePosition(base: baseContent, body: "Position is stable"), nil)
            return
        }

        // Fetch price
        let price = priceFetcher.fetchPrice()
        guard price > 0 else {
            completion(
                mutator.buildPending(
                    base: baseContent,
                    title: "Payment Pending",
                    body: "Open app to process stability payment"
                ),
                true
            )
            return
        }

        // Calculate stability payment
        let stableUSDValue = Double(backingSats) / Constants.satsInBTC * price
        let targetUSD = channelState.expectedUSD
        let dollarsFromPar = stableUSDValue - targetUSD
        let percentFromPar = targetUSD > 0 ? abs(dollarsFromPar / targetUSD) * 100.0 : 0.0

        // Within threshold - no payment needed
        guard percentFromPar >= Constants.stabilityThresholdPercent && abs(dollarsFromPar) >= 0.25 else {
            completion(mutator.buildStablePosition(base: baseContent, body: "Position is stable"), nil)
            return
        }

        // User is above expected (price rose) - should pay LSP
        guard stableUSDValue > targetUSD else {
            completion(mutator.buildStablePosition(base: baseContent, body: "Position is stable"), nil)
            return
        }

        // Calculate amount
        let dollarsAbs = abs(dollarsFromPar)
        let btcAmount = dollarsAbs / price
        let amountMsat = UInt64(btcAmount * Constants.satsInBTC * 1000)
        let amountSats = amountMsat / 1000

        // Claim slot
        guard db.claimPendingSend(amountMsat: amountMsat, price: price) else {
            completion(
                mutator.buildPending(
                    base: baseContent,
                    title: "Payment Pending",
                    body: "Open app to process stability payment"
                ),
                true
            )
            return
        }

        // Send keysend
        do {
            var channelId = channelState.channelId
            if channelId.isEmpty {
                let userChannelId = channelState.userChannelId
                if let activeChannel = node.listChannels().first(where: { userChannelId == "\($0.userChannelId)" }) {
                    channelId = "\(activeChannel.channelId)"
                }
            }
            guard !channelId.isEmpty else {
                completion(
                    mutator.buildPending(
                        base: baseContent,
                        title: "Payment Pending",
                        body: "Open app to process stability payment"
                    ),
                    true
                )
                return
            }

            var entropyBytes = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, entropyBytes.count, &entropyBytes)
            let settlementId = entropyBytes.map { String(format: "%02x", $0) }.joined()
            let createdAt = UInt64(Date().timeIntervalSince1970)
            let expiresAt = createdAt + 1209600 // 14 days

            let payloadDict: [String: Any] = [
                "type": "STABILITY_PAYMENT_V1",
                "settlement_id": settlementId,
                "channel_id": channelId.lowercased(),
                "amount_msat": amountMsat,
                "direction": "user_to_lsp",
                "expected_usd": targetUSD,
                "created_at": createdAt,
                "expires_at": expiresAt
            ]

            guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadDict),
                  let payloadStr = String(data: payloadData, encoding: .utf8) else {
                throw NSError(
                    domain: "StableChannels",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to serialize payload"]
                )
            }

            let domain = "stablechannels-stability-payment-v1"
            let signature = try node.signMessage(msg: Array("\(domain)\n\(payloadStr)".utf8))

            let envelopeDict: [String: Any] = [
                "payload": payloadStr,
                "signature": signature
            ]

            guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelopeDict),
                  let envelopeStr = String(data: envelopeData, encoding: .utf8) else {
                throw NSError(
                    domain: "StableChannels",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to serialize envelope"]
                )
            }

            let markerRecord = CustomTlvRecord(typeNum: Constants.stableChannelTLVType, value: Data([1]))
            let signedRecord = CustomTlvRecord(typeNum: Constants.signedStabilityTLVType, value: Data(envelopeStr.utf8))

            let paymentId = try node.spontaneousPayment().sendWithCustomTlvs(
                amountMsat: amountMsat,
                nodeId: Constants.lspPubkey,
                routeParameters: nil,
                customTlvs: [markerRecord, signedRecord]
            )

            // Payment ID Guard
            let guardSaved = db.setPendingSendPaymentId(paymentId: "\(paymentId)")

            // Update cooldown
            shared?.set(Date().timeIntervalSince1970, forKey: "nse_last_stability_sent")
            shared?.synchronize()

            guard guardSaved else {
                completion(
                    mutator.buildPending(
                        base: baseContent,
                        title: "Payment Sent",
                        body: "Open app to finish syncing the stability payment"
                    ),
                    true
                )
                return
            }

            // Record payment
            let result = db.recordPayment(
                paymentId: "\(paymentId)",
                paymentType: "stability",
                direction: "sent",
                amountMsat: amountMsat,
                amountUSD: dollarsAbs,
                btcPrice: price,
                backingDeltaSats: -Int64(amountSats),
                userChannelId: channelState.userChannelId
            )

            switch result {
            case .inserted, .duplicate:
                db.clearPendingSend()
                completion(mutator.buildForSent(base: baseContent, amountSats: amountSats, dollars: dollarsAbs), false)
            case .failed, .missingChannelRow:
                completion(
                    mutator
                        .buildPending(
                            base: baseContent,
                            title: "Payment Sent",
                            body: "Open app to finish syncing the stability payment"
                        ),
                    true
                )
            }
        } catch {
            db.clearPendingSend()
            completion(
                mutator.buildPending(
                    base: baseContent,
                    title: "Payment Pending",
                    body: "Open app to process stability payment"
                ),
                true
            )
        }
    }
}
