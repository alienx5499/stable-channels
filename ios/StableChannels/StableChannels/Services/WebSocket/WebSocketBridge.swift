// WebSocketBridge.swift
// Bridge between AppState and WebSocketEvents. Implements the reading/writing
// protocols so the event handler can access AppState state without importing it.

import Foundation
import Observation

@MainActor
final class WebSocketBridge: WebSocketEventReading, WebSocketEventWriting {
    private weak var appState: AppState?

    private init() {}

    static func placeholder() -> WebSocketBridge {
        WebSocketBridge()
    }

    func bind(appState: AppState) {
        self.appState = appState
    }

    // MARK: - WebSocketEventReading

    var databaseService: DatabaseService? { appState?.databaseService }
    var isChannelClosing: Bool { appState?.isChannelClosing ?? false }
    var isSweeping: Bool { appState?.isSweeping ?? false }
    var pendingSplice: PendingSplice? { appState?.pendingSplice }
    var onchainBalanceSats: UInt64 { appState?.onchainBalanceSats ?? 0 }
    var prevOnchainSats: UInt64 {
        get { appState?.prevOnchainSats ?? 0 }
        set { appState?.prevOnchainSats = newValue }
    }

    var stableChannel: StableChannel { appState?.stableChannel ?? .default }
    var btcPrice: Double { appState?.btcPrice ?? 0 }

    // MARK: - WebSocketEventWriting

    var paymentFlash: Bool {
        get { appState?.paymentFlash ?? false }
        set { appState?.paymentFlash = newValue }
    }

    func closeTxidResolved(opId: String, closingTxid: String) {
        appState?.handleCloseTxidResolved(opId: opId, closingTxid: closingTxid)
    }

    func receiveTxidResolved(_ txid: String) {
        appState?.transactionLinkService.setReceiveTxid(txid)
    }
}
