import Foundation
import SQLite3

final class InboundSettlementRepository {
    private let rawSQL: RawSQL

    init(rawSQL: RawSQL) {
        self.rawSQL = rawSQL
    }

    func registerInboundStabilitySettlement(
        settlementId: String,
        paymentId: String,
        channelId: String,
        amountMsat: UInt64,
        direction: String,
        envelope: String
    ) throws -> InboundStabilityRegistration {
        return try rawSQL.inTransaction(mode: "IMMEDIATE") {
            let limitSecs = Int64(Constants.stabilityPaymentAuthTTLSecs + Constants.stabilityPaymentClockSkewSecs)
            try rawSQL.execute(
                "DELETE FROM inbound_stability_settlements WHERE state IN ('applied', 'invalid') AND updated_at < strftime('%s', 'now') - ?",
                params: [.integer(limitSecs)]
            )

            let changes = try rawSQL.executeReturningChanges(
                "INSERT OR IGNORE INTO inbound_stability_settlements (settlement_id, payment_id, channel_id, amount_msat, direction, envelope) VALUES (?, ?, ?, ?, ?, ?)",
                params: [
                    .text(settlementId),
                    .text(paymentId),
                    .text(channelId),
                    .integer(Int64(amountMsat)),
                    .text(direction),
                    .text(envelope)
                ]
            )

            let rows = try rawSQL.query(
                "SELECT payment_id, channel_id, amount_msat, direction, envelope, state FROM inbound_stability_settlements WHERE settlement_id = ?",
                params: [.text(settlementId)]
            )
            guard let existing = rows.first else {
                throw DatabaseError.executeFailed("Failed to fetch inbound stability settlement after insert")
            }

            let existingPaymentId = existing[0] as? String ?? ""
            let existingChannelId = existing[1] as? String ?? ""
            let existingAmountMsat = UInt64(existing[2] as? Int64 ?? 0)
            let existingDirection = existing[3] as? String ?? ""
            let existingEnvelope = existing[4] as? String ?? ""
            let state = existing[5] as? String ?? ""

            if existingPaymentId != paymentId ||
                existingChannelId != channelId ||
                existingAmountMsat != amountMsat ||
                existingDirection != direction ||
                existingEnvelope != envelope {
                throw DatabaseError.executeFailed("conflicting inbound stability settlement replay")
            }

            if changes == 1 {
                return .new
            }

            if let reg = InboundStabilityRegistration(rawValue: state) {
                return reg
            }
            return .new
        }
    }

    func finishInboundStabilitySettlement(
        settlementId: String,
        state: String,
        reason: String?
    ) throws {
        try rawSQL.execute(
            "UPDATE inbound_stability_settlements SET state = ?, reason = ?, updated_at = strftime('%s', 'now') WHERE settlement_id = ? AND state = 'pending'",
            params: [.text(state), reason.map { .text($0) } ?? .null, .text(settlementId)]
        )
    }

    func inboundStabilitySettlementReceivedAt(settlementId: String) throws -> UInt64? {
        let rows = try rawSQL.query(
            "SELECT created_at FROM inbound_stability_settlements WHERE settlement_id = ?",
            params: [.text(settlementId)]
        )
        if let val = rows.first?.first as? Int64 {
            return UInt64(val)
        }
        return nil
    }

    func recordSignedStabilityPaymentAndUpdateAllocation(
        paymentId: String,
        settlementId: String,
        amountMsat: UInt64,
        amountUSD: Double?,
        btcPrice: Double?,
        userChannelId: String,
        backingSatsBefore _: UInt64,
        backingSatsAfter: UInt64,
        nativeSatsAfter: UInt64
    ) throws -> PaymentPersistenceResult {
        return try rawSQL.inTransaction(mode: "IMMEDIATE") {
            let existing = try rawSQL.query(
                "SELECT id FROM payments WHERE payment_id = ?",
                params: [.text(paymentId)]
            )
            if !existing.isEmpty {
                try rawSQL.execute(
                    "UPDATE inbound_stability_settlements SET state = 'applied', updated_at = strftime('%s', 'now') WHERE settlement_id = ?",
                    params: [.text(settlementId)]
                )
                return PaymentPersistenceResult(isNewPayment: false, backingSats: backingSatsAfter)
            }

            try rawSQL.execute(
                "INSERT INTO payments (payment_id, payment_type, direction, amount_msat, amount_usd, btc_price, status) VALUES (?, 'stability', 'received', ?, ?, ?, 'completed')",
                params: [
                    .text(paymentId),
                    .integer(Int64(amountMsat)),
                    amountUSD.map { .real($0) } ?? .null,
                    btcPrice.map { .real($0) } ?? .null
                ]
            )

            try rawSQL.execute(
                "UPDATE channels SET stable_sats = ?, native_sats = ?, updated_at = strftime('%s', 'now') WHERE user_channel_id = ?",
                params: [
                    .integer(Int64(backingSatsAfter)),
                    .integer(Int64(nativeSatsAfter)),
                    .text(userChannelId)
                ]
            )

            try rawSQL.execute(
                "UPDATE inbound_stability_settlements SET state = 'applied', updated_at = strftime('%s', 'now') WHERE settlement_id = ? AND state = 'pending'",
                params: [.text(settlementId)]
            )

            return PaymentPersistenceResult(isNewPayment: true, backingSats: backingSatsAfter)
        }
    }
}
