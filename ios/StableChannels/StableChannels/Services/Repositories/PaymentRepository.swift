import Foundation
import SQLite3

final class PaymentRepository {
    private let rawSQL: RawSQL

    init(rawSQL: RawSQL) {
        self.rawSQL = rawSQL
    }

    func paymentExists(txid: String, excludePaymentId: String) -> Bool {
        do {
            let rows = try rawSQL.query(
                "SELECT 1 FROM payments WHERE txid = ? AND payment_id != ? LIMIT 1",
                params: [.text(txid), .text(excludePaymentId)]
            )
            return !rows.isEmpty
        } catch {
            return false
        }
    }

    func deletePayment(paymentId: String) {
        do {
            try rawSQL.execute("DELETE FROM payments WHERE payment_id = ?", params: [.text(paymentId)])
        } catch {
            // Ignore
        }
    }

    func recordPayment(
        paymentId: String?,
        paymentType: String,
        direction: String,
        amountMsat: UInt64,
        amountUSD: Double?,
        btcPrice: Double?,
        counterparty: String?,
        status: String,
        txid: String? = nil,
        address: String? = nil
    ) throws -> Bool {
        if let pid = paymentId, !pid.isEmpty {
            let existing = try rawSQL.query(
                "SELECT id FROM payments WHERE payment_id = ?",
                params: [.text(pid)]
            )
            if !existing.isEmpty {
                return false
            }
        }

        // OR IGNORE: this path is not transactional, so the existence check above
        // can race the NSE. The unique payment_id index turns the losing insert
        // into a no-op instead of a duplicate row (or, without it, an error).
        let sql = """
            INSERT OR IGNORE INTO payments (payment_id, payment_type, direction, amount_msat, amount_usd, btc_price, counterparty, status, txid, address)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let inserted = try rawSQL.executeReturningChanges(sql, params: [
            paymentId.map { .text($0) } ?? .null,
            .text(paymentType), .text(direction), .integer(Int64(amountMsat)),
            amountUSD.map { .real($0) } ?? .null,
            btcPrice.map { .real($0) } ?? .null,
            counterparty.map { .text($0) } ?? .null,
            .text(status),
            txid.map { .text($0) } ?? .null,
            address.map { .text($0) } ?? .null
        ])
        return inserted > 0
    }

    func updatePaymentStatus(paymentId: String, status: String, feeMsat: UInt64? = nil) throws {
        if let fee = feeMsat {
            try rawSQL.execute(
                "UPDATE payments SET status = ?, fee_msat = ? WHERE payment_id = ? AND status = 'pending'",
                params: [.text(status), .integer(Int64(fee)), .text(paymentId)]
            )
        } else {
            try rawSQL.execute(
                "UPDATE payments SET status = ? WHERE payment_id = ? AND status = 'pending'",
                params: [.text(status), .text(paymentId)]
            )
        }
    }

    @discardableResult
    func updatePaymentTxid(paymentId: String, txid: String, status: String) -> Bool {
        do {
            try rawSQL.execute(
                """
                UPDATE payments
                SET txid = ?, status = ?
                WHERE payment_id = ?
                """,
                params: [.text(txid), .text(status), .text(paymentId)]
            )
            return true
        } catch {
            return false
        }
    }

    func failPaymentByTxid(txid: String) throws {
        try rawSQL.execute(
            "UPDATE payments SET status = 'failed' WHERE txid = ? AND status = 'pending'",
            params: [.text(txid)]
        )
    }

    func latestReceivedPayment() -> PaymentRecord? {
        let sql = """
        SELECT id, payment_id, payment_type, direction, amount_msat, amount_usd, btc_price,
        counterparty, status, created_at, fee_msat, txid, address, confirmations, tx_block_height
        FROM payments
        WHERE direction = "received"
        AND NOT (payment_type = 'lightning' AND amount_msat < 1000)
        ORDER BY id DESC LIMIT 1
        """
        guard let row = try? rawSQL.query(sql, params: []).first else { return nil }
        return paymentRecord(from: row)
    }

    func payment(paymentId: String) -> PaymentRecord? {
        let sql = """
        SELECT id, payment_id, payment_type, direction, amount_msat, amount_usd, btc_price,
        counterparty, status, created_at, fee_msat, txid, address, confirmations, tx_block_height
        FROM payments
        WHERE payment_id = ?
        ORDER BY id DESC LIMIT 1
        """
        guard let row = try? rawSQL.query(sql, params: [.text(paymentId)]).first else { return nil }
        return paymentRecord(from: row)
    }

    func payment(txid: String) -> PaymentRecord? {
        let sql = """
        SELECT id, payment_id, payment_type, direction, amount_msat, amount_usd, btc_price,
        counterparty, status, created_at, fee_msat, txid, address, confirmations, tx_block_height
        FROM payments
        WHERE txid = ?
        ORDER BY id DESC LIMIT 1
        """
        guard let row = try? rawSQL.query(sql, params: [.text(txid)]).first else { return nil }
        return paymentRecord(from: row)
    }

    func paymentsNeedingConfirmation() throws -> [PaymentRecord] {
        let required = ConfirmationPolicy.requiredConfirmations
        let sql = """
        SELECT id, payment_id, payment_type, direction, amount_msat, amount_usd, btc_price,
        counterparty, status, created_at, fee_msat, txid, address, confirmations, tx_block_height
        FROM payments
        WHERE txid IS NOT NULL
        AND txid != ''
        AND payment_type IN ('onchain', 'splice_in', 'splice_out', 'channel_close')
        AND status != 'failed'
        AND (confirmations IS NULL OR confirmations < ?)
        ORDER BY created_at DESC
        LIMIT 50
        """
        let rows = try rawSQL.query(
            sql,
            params: [.integer(Int64(required))]
        )
        return rows.map { row in
            paymentRecord(from: row)
        }
    }

    func getPayment(byId id: Int64) throws -> PaymentRecord? {
        let sql = """
        SELECT id, payment_id, payment_type, direction, amount_msat, amount_usd, btc_price,
        counterparty, status, created_at, fee_msat, txid, address, confirmations, tx_block_height
        FROM payments WHERE id = ? LIMIT 1
        """
        let rows = try rawSQL.query(sql, params: [.integer(id)])
        guard let row = rows.first else { return nil }
        return paymentRecord(from: row)
    }

    func updateConfirmations(paymentId: Int64, txBlockHeight: UInt32, currentBlockHeight: UInt32) throws {
        let required = ConfirmationPolicy.requiredConfirmations
        let rawConfs = max(Int(currentBlockHeight) - Int(txBlockHeight) + 1, 0)
        let confs = min(rawConfs, required)
        let status = confs >= required ? "completed" : "pending"
        try rawSQL.execute(
            "UPDATE payments SET confirmations = ?, tx_block_height = ?, status = ? WHERE id = ?",
            params: [
                .integer(Int64(confs)),
                .integer(Int64(txBlockHeight)),
                .text(status),
                .integer(paymentId)
            ]
        )
    }

    func getRecentPayments(limit: Int) throws -> [PaymentRecord] {
        let sql = """
            SELECT id, payment_id, payment_type, direction, amount_msat, amount_usd, btc_price,
                   counterparty, status, created_at, fee_msat, txid, address, confirmations, tx_block_height
            FROM payments
            WHERE NOT (payment_type = 'lightning' AND amount_msat < 1000)
            ORDER BY id DESC LIMIT ?
        """
        let rows = try rawSQL.query(sql, params: [.integer(Int64(limit))])
        return rows.map { row in
            paymentRecord(from: row)
        }
    }

    func updateTradeStatus(_ tradeId: Int64, status: String) throws {
        try rawSQL.execute(
            "UPDATE trades SET status = ? WHERE id = ?",
            params: [.text(status), .integer(tradeId)]
        )
    }

    func recordPaymentAndMaybeUpdateBacking(
        paymentId: String?,
        paymentType: String,
        direction: String,
        amountMsat: UInt64,
        amountUSD: Double?,
        btcPrice: Double?,
        status: String,
        userChannelId: String?,
        backingDeltaSats: Int64?
    ) throws -> PaymentPersistenceResult {
        try rawSQL.inTransaction(mode: "IMMEDIATE") {
            if let pid = paymentId, !pid.isEmpty {
                let existing = try rawSQL.query(
                    "SELECT id FROM payments WHERE payment_id = ?",
                    params: [.text(pid)]
                )
                if !existing.isEmpty {
                    let backing = try authoritativeBacking(
                        userChannelId: userChannelId,
                        required: backingDeltaSats != nil
                    )
                    return PaymentPersistenceResult(isNewPayment: false, backingSats: backing)
                }
            }

            try rawSQL.execute(
                "INSERT INTO payments (payment_id, payment_type, direction, amount_msat, amount_usd, btc_price, status) VALUES (?, ?, ?, ?, ?, ?, ?)",
                params: [
                    paymentId.map { .text($0) } ?? .null,
                    .text(paymentType), .text(direction), .integer(Int64(amountMsat)),
                    amountUSD.map { .real($0) } ?? .null,
                    btcPrice.map { .real($0) } ?? .null,
                    .text(status)
                ]
            )
            var resultingBacking: UInt64?
            if let delta = backingDeltaSats {
                guard let ucid = userChannelId, !ucid.isEmpty else {
                    throw DatabaseError.executeFailed("userChannelId required for backing update")
                }
                let rows = try rawSQL.query(
                    "SELECT stable_sats FROM channels WHERE user_channel_id = ?",
                    params: [.text(ucid)]
                )
                guard let current = rows.first?.int64(0) else {
                    throw DatabaseError.missingChannelRow(ucid)
                }
                let newBacking = max(0, current + delta)
                if current + delta < 0 {
                    AuditService.log("BACKING_CLAMPED", data: [
                        "user_channel_id": ucid,
                        "current_backing_sats": "\(current)",
                        "delta_sats": "\(delta)"
                    ])
                }
                try rawSQL.execute(
                    "UPDATE channels SET stable_sats = ?, updated_at = strftime('%s', 'now') WHERE user_channel_id = ?",
                    params: [.integer(newBacking), .text(ucid)]
                )
                let changedRows = rawSQL.changes
                if changedRows != 1 {
                    throw DatabaseError.executeFailed(
                        "backing UPDATE affected \(changedRows) rows for user_channel_id=\(ucid)"
                    )
                }
                resultingBacking = UInt64(newBacking)
            }
            return PaymentPersistenceResult(
                isNewPayment: true,
                backingSats: resultingBacking
            )
        }
    }

    private func authoritativeBacking(
        userChannelId: String?,
        required: Bool
    ) throws -> UInt64? {
        guard required else { return nil }
        guard let ucid = userChannelId, !ucid.isEmpty else {
            throw DatabaseError.executeFailed("userChannelId required to load backing")
        }
        let rows = try rawSQL.query(
            "SELECT stable_sats FROM channels WHERE user_channel_id = ?",
            params: [.text(ucid)]
        )
        guard let value = rows.first?.int64(0) else {
            throw DatabaseError.missingChannelRow(ucid)
        }
        guard value >= 0 else {
            throw DatabaseError.executeFailed(
                "No valid backing row for user_channel_id=\(ucid)"
            )
        }
        return UInt64(value)
    }

    func recentConfirmedPayments(confirmedAfterHeight: UInt32) throws -> [PaymentRecord] {
        let sql = """
        SELECT id, payment_id, payment_type, direction, amount_msat, amount_usd,
               btc_price, counterparty, status, created_at, fee_msat, txid, address,
               confirmations, tx_block_height
        FROM payments
        WHERE (txid IS NOT NULL OR address IS NOT NULL)
          AND status = 'completed'
          AND tx_block_height IS NOT NULL
          AND tx_block_height >= ?
        ORDER BY tx_block_height DESC;
        """
        let rows = try rawSQL.query(sql, params: [.integer(Int64(confirmedAfterHeight))])
        return rows.map { row in
            paymentRecord(from: row)
        }
    }

    func downgradePaymentToPending(paymentId: Int64) throws {
        let sql = """
        UPDATE payments
        SET status = 'pending', confirmations = 0, tx_block_height = NULL
        WHERE id = ?;
        """
        try rawSQL.execute(sql, params: [.integer(paymentId)])
    }

    private func paymentRecord(from row: [Any?]) -> PaymentRecord {
        PaymentRecord(
            id: row.int64(0),
            paymentId: row.optString(1),
            paymentType: row.string(2, default: "manual"),
            direction: row.string(3),
            amountMsat: row.uInt64(4),
            amountUSD: row.optDouble(5),
            btcPrice: row.optDouble(6),
            counterparty: row.optString(7),
            status: row.string(8),
            createdAt: row.int64(9),
            feeMsat: row.uInt64(10),
            txid: row.optString(11),
            address: row.optString(12),
            confirmations: row.uInt32(13),
            txBlockHeight: row.optUInt32(14)
        )
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
