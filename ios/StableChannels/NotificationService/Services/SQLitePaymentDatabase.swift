import Foundation
import SQLite3
import LDKNode

/// SQLite implementation of PaymentDatabase
final class SQLitePaymentDatabase: PaymentDatabase {
    private let dbPath: String
    private static let satsInBTC: Double = 100_000_000.0
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let pendingSendTableSQL = """
    CREATE TABLE IF NOT EXISTS pending_stability_send (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    payment_id TEXT NOT NULL,
    amount_msat INTEGER NOT NULL,
    price REAL NOT NULL,
    created_at INTEGER NOT NULL
    )
    """

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    private func openDB(write: Bool = true) -> OpaquePointer? {
        var db: OpaquePointer?
        let flags = write ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(dbPath, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        sqlite3_busy_timeout(db, 2000)
        return db
    }

    func paymentExists(paymentId: String) -> Bool {
        guard let db = openDB(write: false) else { return false }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM payments WHERE payment_id = ?", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(
            stmt,
            1,
            (paymentId as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )
        return sqlite3_step(stmt) == SQLITE_ROW
    }

    func recordPayment(
        paymentId: String,
        paymentType: String,
        direction: String,
        amountMsat: UInt64,
        amountUSD: Double,
        btcPrice: Double,
        backingDeltaSats: Int64?,
        userChannelId: String?
    ) -> PaymentInsertResult {
        guard let db = openDB() else { return .failed }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return .failed }

        // Dedup check
        if !paymentId.isEmpty {
            var checkStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT 1 FROM payments WHERE payment_id = ?", -1, &checkStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(
                    checkStmt,
                    1,
                    (paymentId as NSString).utf8String,
                    -1,
                    SQLITE_TRANSIENT
                )
                if sqlite3_step(checkStmt) == SQLITE_ROW {
                    sqlite3_finalize(checkStmt)
                    sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                    return .duplicate
                }
                sqlite3_finalize(checkStmt)
            }
        }

        // Insert payment
        var stmt: OpaquePointer?
        let insertSql = "INSERT INTO payments (payment_id, payment_type, direction, amount_msat, amount_usd, btc_price, status) VALUES (?, ?, ?, ?, ?, ?, 'completed')"
        guard sqlite3_prepare_v2(db, insertSql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }
        defer { sqlite3_finalize(stmt) }

        if !paymentId.isEmpty {
            sqlite3_bind_text(
                stmt,
                1,
                (paymentId as NSString).utf8String,
                -1,
                SQLITE_TRANSIENT
            )
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(
            stmt,
            2,
            (paymentType as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )
        sqlite3_bind_text(
            stmt,
            3,
            (direction as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )
        sqlite3_bind_int64(stmt, 4, Int64(amountMsat))
        sqlite3_bind_double(stmt, 5, amountUSD)
        sqlite3_bind_double(stmt, 6, btcPrice)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }

        // Update backing if needed
        if let delta = backingDeltaSats {
            guard let ucid = userChannelId, !ucid.isEmpty else {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return .missingChannelRow
            }
            if !updateBacking(db: db, ucid: ucid, delta: delta) {
                sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
                return .missingChannelRow // originally returned missingChannelRow if it fails to update or missing
                // channel
            }
        }

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { return .failed }
        return .inserted
    }

    private func updateBacking(db: OpaquePointer, ucid: String, delta: Int64) -> Bool {
        var selectStmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT stable_sats FROM channels WHERE user_channel_id = ?",
            -1,
            &selectStmt,
            nil
        ) == SQLITE_OK else {
            return false
        }
        sqlite3_bind_text(
            selectStmt,
            1,
            (ucid as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )
        guard sqlite3_step(selectStmt) == SQLITE_ROW else {
            sqlite3_finalize(selectStmt)
            return false
        }
        let currentBacking = sqlite3_column_int64(selectStmt, 0)
        sqlite3_finalize(selectStmt)

        let newBacking = max(0, currentBacking + delta)

        var updateStmt: OpaquePointer?
        let sql = "UPDATE channels SET stable_sats = ?, updated_at = strftime('%s', 'now') WHERE user_channel_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &updateStmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(updateStmt) }

        sqlite3_bind_int64(updateStmt, 1, newBacking)
        sqlite3_bind_text(
            updateStmt,
            2,
            (ucid as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )

        return sqlite3_step(updateStmt) == SQLITE_DONE && sqlite3_changes(db) == 1
    }

    func readChannelState() -> ChannelState? {
        guard let db = openDB(write: false) else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = """
        SELECT expected_usd, stable_sats, receiver_sats, latest_price, native_sats, user_channel_id, channel_id
        FROM channels
        WHERE user_channel_id IS NOT NULL AND user_channel_id != ''
        ORDER BY updated_at DESC, channel_id DESC
        LIMIT 1
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return ChannelState(
            expectedUSD: sqlite3_column_double(stmt, 0),
            backingSats: UInt64(sqlite3_column_int64(stmt, 1)),
            nativeSats: UInt64(sqlite3_column_int64(stmt, 4)),
            receiverSats: UInt64(sqlite3_column_int64(stmt, 2)),
            latestPrice: sqlite3_column_double(stmt, 3),
            userChannelId: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "",
            channelId: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
        )
    }

    func activeUserChannelId() -> String? {
        readChannelState()?.userChannelId
    }

    func applySyncMessage(expectedUSD: Double, payloadUserChannelId: String?, priceFetcher: PriceFetcher) -> Bool {
        let ucid: String
        if let payloadUserChannelId, !payloadUserChannelId.isEmpty {
            ucid = payloadUserChannelId
        } else if let active = activeUserChannelId() {
            ucid = active
        } else {
            return false
        }

        guard let db = openDB() else { return false }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return false }

        // Read current state
        var selectStmt: OpaquePointer?
        let selectSql = "SELECT stable_sats, receiver_sats, latest_price FROM channels WHERE user_channel_id = ?"
        guard sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        sqlite3_bind_text(
            selectStmt,
            1,
            (ucid as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )
        guard sqlite3_step(selectStmt) == SQLITE_ROW else {
            sqlite3_finalize(selectStmt)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        let currentBacking = UInt64(sqlite3_column_int64(selectStmt, 0))
        let receiverSats = UInt64(sqlite3_column_int64(selectStmt, 1))
        let price = sqlite3_column_double(selectStmt, 2)
        sqlite3_finalize(selectStmt)

        // Calculate new backing
        var finalPrice = price
        if finalPrice <= 0 {
            finalPrice = priceFetcher.fetchPrice()
        }

        let newBacking: UInt64
        if finalPrice > 0 {
            newBacking = UInt64(max(0.0, expectedUSD / finalPrice * Self.satsInBTC))
        } else {
            newBacking = currentBacking
        }
        let newNative = receiverSats >= newBacking ? receiverSats - newBacking : 0

        // Update
        var updateStmt: OpaquePointer?
        let updateSql = """
        UPDATE channels
        SET expected_usd = ?, stable_sats = ?, native_sats = ?, latest_price = ?, updated_at = strftime('%s', 'now')
        WHERE user_channel_id = ?
        """
        guard sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        defer { sqlite3_finalize(updateStmt) }

        sqlite3_bind_double(updateStmt, 1, expectedUSD)
        sqlite3_bind_int64(updateStmt, 2, Int64(newBacking))
        sqlite3_bind_int64(updateStmt, 3, Int64(newNative))
        sqlite3_bind_double(updateStmt, 4, finalPrice)
        sqlite3_bind_text(
            updateStmt,
            5,
            (ucid as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )

        guard sqlite3_step(updateStmt) == SQLITE_DONE, sqlite3_changes(db) == 1 else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { return false }
        return true
    }

    // MARK: - Pending Send Operations

    func claimPendingSend(amountMsat: UInt64, price: Double) -> Bool {
        guard let db = openDB() else { return false }
        defer { sqlite3_close(db) }

        _ = sqlite3_exec(db, Self.pendingSendTableSQL, nil, nil, nil)

        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return false }

        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT 1 FROM pending_stability_send WHERE id = 1", -1, &checkStmt, nil) ==
            SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        let alreadyClaimed = sqlite3_step(checkStmt) == SQLITE_ROW
        sqlite3_finalize(checkStmt)

        if alreadyClaimed {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }

        var stmt: OpaquePointer?
        let sql = "INSERT INTO pending_stability_send (id, payment_id, amount_msat, price, created_at) VALUES (1, '', ?, ?, ?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, Int64(amountMsat))
        sqlite3_bind_double(stmt, 2, price)
        sqlite3_bind_int64(stmt, 3, Int64(Date().timeIntervalSince1970))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }

        return sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
    }

    func loadPendingSend() -> PendingOutgoingStabilityPayment? {
        guard let db = openDB(write: false) else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT payment_id, amount_msat, price, created_at FROM pending_stability_send WHERE id = 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        return PendingOutgoingStabilityPayment(
            paymentId: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "",
            amountMsat: UInt64(sqlite3_column_int64(stmt, 1)),
            btcPrice: sqlite3_column_double(stmt, 2),
            createdAt: sqlite3_column_int64(stmt, 3)
        )
    }

    func clearPendingSend() {
        guard let db = openDB() else { return }
        sqlite3_exec(db, "DELETE FROM pending_stability_send WHERE id = 1", nil, nil, nil)
        sqlite3_close(db)
    }

    func reconcilePendingOutgoingPayment(node: LDKNode.Node) -> Bool {
        guard var pending = loadPendingSend() else { return true }

        if pending.paymentId.isEmpty {
            let candidates = node.listPayments().filter { payment in
                guard payment.direction == .outbound,
                      payment.amountMsat == pending.amountMsat,
                      Int64(payment.latestUpdateTimestamp) >= pending.createdAt - 10,
                      case .spontaneous = payment.kind else { return false }
                return true
            }

            if let succeeded = candidates.first(where: { $0.status == .succeeded }) {
                _ = setPendingSendPaymentId(paymentId: "\(succeeded.id)")
                pending = PendingOutgoingStabilityPayment(
                    paymentId: "\(succeeded.id)",
                    amountMsat: pending.amountMsat,
                    btcPrice: pending.btcPrice,
                    createdAt: pending.createdAt
                )
            } else if candidates.contains(where: { $0.status == .pending }) {
                return false
            } else if candidates
                .contains(where: { $0.status == .failed }) || Int64(Date().timeIntervalSince1970) - pending
                .createdAt > 120 {
                clearPendingSend()
                return true
            } else {
                return false
            }
        }

        let amountUSD = pending.btcPrice > 0 ? (Double(pending.amountMsat) / 1000.0 / Self.satsInBTC) * pending
            .btcPrice : 0.0
        let result = recordPayment(
            paymentId: pending.paymentId,
            paymentType: "stability",
            direction: "sent",
            amountMsat: pending.amountMsat,
            amountUSD: amountUSD,
            btcPrice: pending.btcPrice,
            backingDeltaSats: -Int64(pending.amountMsat / 1000),
            userChannelId: activeUserChannelId()
        )

        switch result {
        case .inserted, .duplicate:
            clearPendingSend()
            return true
        case .failed, .missingChannelRow:
            return false
        }
    }

    func setPendingSendPaymentId(paymentId: String) -> Bool {
        guard let db = openDB() else { return false }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE pending_stability_send SET payment_id = ? WHERE id = 1", -1, &stmt, nil) ==
            SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(
            stmt,
            1,
            (paymentId as NSString).utf8String,
            -1,
            SQLITE_TRANSIENT
        )
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    func registerInboundStabilitySettlement(
        settlementId: String,
        paymentId: String,
        channelId: String,
        amountMsat: UInt64,
        direction: String,
        envelope: String
    ) -> InboundStabilityRegistration? {
        guard let db = openDB() else { return nil }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return nil }

        // Prune expired tombstones
        let limitSecs = Int64(Constants.stabilityPaymentAuthTTLSecs + Constants.stabilityPaymentClockSkewSecs)
        var pruneStmt: OpaquePointer?
        if sqlite3_prepare_v2(
            db,
            "DELETE FROM inbound_stability_settlements WHERE state IN ('applied', 'invalid') AND updated_at < strftime('%s', 'now') - ?",
            -1,
            &pruneStmt,
            nil
        ) == SQLITE_OK {
            sqlite3_bind_int64(pruneStmt, 1, limitSecs)
            sqlite3_step(pruneStmt)
            sqlite3_finalize(pruneStmt)
        }

        // Try to insert OR IGNORE
        var insertStmt: OpaquePointer?
        let insertSql = "INSERT OR IGNORE INTO inbound_stability_settlements (settlement_id, payment_id, channel_id, amount_msat, direction, envelope) VALUES (?, ?, ?, ?, ?, ?)"
        guard sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return nil
        }
        sqlite3_bind_text(insertStmt, 1, (settlementId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insertStmt, 2, (paymentId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insertStmt, 3, (channelId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(insertStmt, 4, Int64(amountMsat))
        sqlite3_bind_text(insertStmt, 5, (direction as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(insertStmt, 6, (envelope as NSString).utf8String, -1, SQLITE_TRANSIENT)

        let insertResult = sqlite3_step(insertStmt)
        sqlite3_finalize(insertStmt)

        guard insertResult == SQLITE_DONE else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return nil
        }

        let changes = sqlite3_changes(db)

        // Read current state
        var selectStmt: OpaquePointer?
        let selectSql = "SELECT payment_id, channel_id, amount_msat, direction, envelope, state FROM inbound_stability_settlements WHERE settlement_id = ?"
        guard sqlite3_prepare_v2(db, selectSql, -1, &selectStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return nil
        }
        sqlite3_bind_text(selectStmt, 1, (settlementId as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(selectStmt) == SQLITE_ROW else {
            sqlite3_finalize(selectStmt)
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return nil
        }

        let existingPaymentId = sqlite3_column_text(selectStmt, 0).map { String(cString: $0) } ?? ""
        let existingChannelId = sqlite3_column_text(selectStmt, 1).map { String(cString: $0) } ?? ""
        let existingAmountMsat = UInt64(sqlite3_column_int64(selectStmt, 2))
        let existingDirection = sqlite3_column_text(selectStmt, 3).map { String(cString: $0) } ?? ""
        let existingEnvelope = sqlite3_column_text(selectStmt, 4).map { String(cString: $0) } ?? ""
        let state = sqlite3_column_text(selectStmt, 5).map { String(cString: $0) } ?? ""
        sqlite3_finalize(selectStmt)

        // Validate replay fields match exactly
        if existingPaymentId != paymentId ||
            existingChannelId != channelId ||
            existingAmountMsat != amountMsat ||
            existingDirection != direction ||
            existingEnvelope != envelope {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return nil
        }

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            return nil
        }

        if changes == 1 {
            return .new
        }

        return InboundStabilityRegistration(rawValue: state)
    }

    func finishInboundStabilitySettlement(
        settlementId: String,
        state: String,
        reason: String?
    ) -> Bool {
        guard let db = openDB() else { return false }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "UPDATE inbound_stability_settlements SET state = ?, reason = ?, updated_at = strftime('%s', 'now') WHERE settlement_id = ? AND state = 'pending'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (state as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if let reason {
            sqlite3_bind_text(stmt, 2, (reason as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 2)
        }
        sqlite3_bind_text(stmt, 3, (settlementId as NSString).utf8String, -1, SQLITE_TRANSIENT)

        return sqlite3_step(stmt) == SQLITE_DONE
    }

    func inboundStabilitySettlementReceivedAt(settlementId: String) -> UInt64? {
        guard let db = openDB(write: false) else { return nil }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT created_at FROM inbound_stability_settlements WHERE settlement_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (settlementId as NSString).utf8String, -1, SQLITE_TRANSIENT)

        if sqlite3_step(stmt) == SQLITE_ROW {
            return UInt64(sqlite3_column_int64(stmt, 0))
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
    ) -> PaymentInsertResult {
        guard let db = openDB() else { return .failed }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { return .failed }

        // Dedup check on paymentId
        var checkStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT 1 FROM payments WHERE payment_id = ?", -1, &checkStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(checkStmt, 1, (paymentId as NSString).utf8String, -1, SQLITE_TRANSIENT)
            if sqlite3_step(checkStmt) == SQLITE_ROW {
                sqlite3_finalize(checkStmt)

                // Update settlement to applied
                var updateSettlementStmt: OpaquePointer?
                if sqlite3_prepare_v2(
                    db,
                    "UPDATE inbound_stability_settlements SET state = 'applied', updated_at = strftime('%s', 'now') WHERE settlement_id = ?",
                    -1,
                    &updateSettlementStmt,
                    nil
                ) == SQLITE_OK {
                    sqlite3_bind_text(
                        updateSettlementStmt,
                        1,
                        (settlementId as NSString).utf8String,
                        -1,
                        SQLITE_TRANSIENT
                    )
                    sqlite3_step(updateSettlementStmt)
                    sqlite3_finalize(updateSettlementStmt)
                }

                sqlite3_exec(db, "COMMIT", nil, nil, nil)
                return .duplicate
            }
            sqlite3_finalize(checkStmt)
        }

        // Insert payment
        var insertStmt: OpaquePointer?
        let insertSql = "INSERT INTO payments (payment_id, payment_type, direction, amount_msat, amount_usd, btc_price, status) VALUES (?, 'stability', 'received', ?, ?, ?, 'completed')"
        guard sqlite3_prepare_v2(db, insertSql, -1, &insertStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }
        sqlite3_bind_text(insertStmt, 1, (paymentId as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(insertStmt, 2, Int64(amountMsat))
        if let usd = amountUSD {
            sqlite3_bind_double(insertStmt, 3, usd)
        } else {
            sqlite3_bind_null(insertStmt, 3)
        }
        if let price = btcPrice {
            sqlite3_bind_double(insertStmt, 4, price)
        } else {
            sqlite3_bind_null(insertStmt, 4)
        }

        let insertRes = sqlite3_step(insertStmt)
        sqlite3_finalize(insertStmt)
        guard insertRes == SQLITE_DONE else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }

        // Update channels stable_sats and native_sats
        var channelStmt: OpaquePointer?
        let channelSql = "UPDATE channels SET stable_sats = ?, native_sats = ?, updated_at = strftime('%s', 'now') WHERE user_channel_id = ?"
        guard sqlite3_prepare_v2(db, channelSql, -1, &channelStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }
        sqlite3_bind_int64(channelStmt, 1, Int64(backingSatsAfter))
        sqlite3_bind_int64(channelStmt, 2, Int64(nativeSatsAfter))
        sqlite3_bind_text(channelStmt, 3, (userChannelId as NSString).utf8String, -1, SQLITE_TRANSIENT)

        let channelRes = sqlite3_step(channelStmt)
        sqlite3_finalize(channelStmt)
        guard channelRes == SQLITE_DONE else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }

        // Update settlement state to applied
        var applyStmt: OpaquePointer?
        let applySql = "UPDATE inbound_stability_settlements SET state = 'applied', updated_at = strftime('%s', 'now') WHERE settlement_id = ? AND state = 'pending'"
        guard sqlite3_prepare_v2(db, applySql, -1, &applyStmt, nil) == SQLITE_OK else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }
        sqlite3_bind_text(applyStmt, 1, (settlementId as NSString).utf8String, -1, SQLITE_TRANSIENT)

        let applyRes = sqlite3_step(applyStmt)
        sqlite3_finalize(applyStmt)
        guard applyRes == SQLITE_DONE else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return .failed
        }

        guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else {
            return .failed
        }

        return .inserted
    }
}
