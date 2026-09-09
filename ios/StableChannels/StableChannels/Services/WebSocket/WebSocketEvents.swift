// WebSocketEvents.swift
// Handles WebSocket transaction events: tracked outspend, removed, receive.
// Reads state through WebSocketEventReading, writes via WebSocketEventWriting.

import Foundation
import Observation
import SQLite3

@MainActor
protocol WebSocketEventReading: AnyObject {
    var databaseService: DatabaseService? { get }
    var isChannelClosing: Bool { get }
    var isSweeping: Bool { get }
    var pendingSplice: PendingSplice? { get }
    var onchainBalanceSats: UInt64 { get }
    var prevOnchainSats: UInt64 { get set }
    var stableChannel: StableChannel { get }
    var btcPrice: Double { get }
}

protocol WebSocketEventWriting: AnyObject {
    var paymentFlash: Bool { get set }
    func closeTxidResolved(opId: String, closingTxid: String)
    func receiveTxidResolved(_ txid: String)
}

@MainActor
final class WebSocketEvents {
    private weak var reader: WebSocketEventReading?
    private weak var writer: WebSocketEventWriting?

    private let mempoolWebSocket: (any MempoolWebSocketProtocol)?

    init(
        reader: WebSocketEventReading,
        writer: WebSocketEventWriting,
        mempoolWebSocket: (any MempoolWebSocketProtocol)?
    ) {
        self.reader = reader
        self.writer = writer
        self.mempoolWebSocket = mempoolWebSocket
    }

    func handle(event: WebSocketEvent) {
        guard let reader else { return }

        switch event {
        case .trackedOutspend(let trackedTxid, let spendingTxid):
            handleTrackedOutspend(trackedTxid: trackedTxid, spendingTxid: spendingTxid)

        case .removed(let target, let txid):
            handleRemoved(target: target, txid: txid)

        case .receive(let target, let txid, let amountSats):
            handleReceive(target: target, txid: txid, amountSats: amountSats)
        }
    }

    // MARK: - Event Handlers

    private func handleTrackedOutspend(trackedTxid: String, spendingTxid: String) {
        guard reader?.isChannelClosing == true else { return }

        mempoolWebSocket?.untrackTx(trackedTxid)

        guard let db = reader?.databaseService,
              let op = db.pendingOpRepo.fetchPendingOperationByFundingTxid(trackedTxid) else { return }
        writer?.closeTxidResolved(opId: op.opId, closingTxid: spendingTxid)
    }

    private func handleRemoved(target: String, txid: String) {
        guard let reader,
              !reader.isChannelClosing,
              !reader.isSweeping,
              reader.pendingSplice == nil else { return }

        guard let db = reader.databaseService else { return }
        do {
            try db.paymentRepo.failPaymentByTxid(txid: txid)
            let currentOnchain = reader.onchainBalanceSats
            if currentOnchain < reader.prevOnchainSats {
                reader.prevOnchainSats = currentOnchain
            }
            AuditService.log("WEBSOCKET_RBF_FAILED_PAYMENT", data: ["txid": txid, "target": target])
        } catch {
            AuditService.log("WEBSOCKET_RBF_FAIL_FAILED", data: ["error": "\(error)", "txid": txid])
        }
    }

    private func handleReceive(target: String, txid: String, amountSats: Int64) {
        guard let reader,
              !reader.isChannelClosing,
              !reader.isSweeping,
              reader.pendingSplice == nil else { return }

        guard let db = reader.databaseService else { return }

        guard amountSats >= 1000 else { return }

        let price = reader.stableChannel.latestPrice > 0
            ? reader.stableChannel.latestPrice
            : reader.btcPrice
        let amountUSD: Double? = price > 0
            ? Double(amountSats) / 100_000_000.0 * price
            : nil
        let paymentId = "onchain_receive_\(txid)"

        do {
            let recorded = try db.paymentRepo.recordPayment(
                paymentId: paymentId,
                paymentType: "onchain",
                direction: "received",
                amountMsat: UInt64(amountSats * 1000),
                amountUSD: amountUSD,
                btcPrice: price > 0 ? price : nil,
                counterparty: nil,
                status: "pending",
                txid: txid,
                address: target
            )
            if recorded {
                AuditService.log(
                    "WEBSOCKET_INSTANT_PAYMENT_RECORDED",
                    data: ["txid": txid, "sats": "\(amountSats)"]
                )
                writer?.paymentFlash = true
                writer?.receiveTxidResolved(txid)
            }
        } catch {
            AuditService.log("WEBSOCKET_RECORD_PAYMENT_FAILED", data: ["error": "\(error)"])
        }
    }
}
