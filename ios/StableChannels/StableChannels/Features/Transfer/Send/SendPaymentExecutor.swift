import Foundation
import LDKNode

/// Output result from a successfully broadcast payment.
struct SendPaymentResult: Equatable, Sendable {
    let sentAmountSats: UInt64
    let paymentId: String?
    let txid: String?
}

/// Orchestrates payment dispatch across Lightning, LNURL, and Onchain subsystems.
@MainActor
struct SendPaymentExecutor {
    static func execute(
        destination: SendDestination,
        effectiveSats: UInt64,
        feeRateSatVb: UInt64? = nil,
        lnurlParams: LNURLPayParams?,
        lnurlComment: String,
        appState: AppState,
        lnurlService: LNURLServiceProtocol
    ) async throws -> SendPaymentResult {
        let price = appState.accountingBTCPrice

        switch destination {
        case .bolt11(let invoice, _, let msat):
            return try await sendBolt11(
                invoice: invoice,
                msat: msat,
                effectiveSats: effectiveSats,
                price: price,
                appState: appState
            )
        case .bolt12(let offer, _):
            return try await sendBolt12(offer: offer, effectiveSats: effectiveSats, price: price, appState: appState)
        case .lightningAddress, .lnurlPay:
            return try await sendLNURL(
                params: lnurlParams,
                comment: lnurlComment,
                effectiveSats: effectiveSats,
                price: price,
                appState: appState,
                lnurlService: lnurlService
            )
        case .onchain(let address):
            return try await sendOnchain(
                address: address,
                effectiveSats: effectiveSats,
                price: price,
                feeRateSatVb: feeRateSatVb,
                appState: appState
            )
        }
    }

    private static func sendBolt11(
        invoice: Bolt11Invoice,
        msat: UInt64?,
        effectiveSats: UInt64,
        price: Double,
        appState: AppState
    ) async throws -> SendPaymentResult {
        let actualMsat: UInt64
        let paymentId: PaymentId
        if let msat, msat > 0 {
            actualMsat = msat
            try appState.ensureNoUnsettledSurplus(amountMsat: actualMsat)
            paymentId = try appState.nodeService.sendPayment(invoice: invoice)
        } else {
            actualMsat = effectiveSats * 1000
            guard actualMsat > 0 else { throw NSError(
                domain: "Send",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid amount"]
            ) }
            try appState.ensureNoUnsettledSurplus(amountMsat: actualMsat)
            paymentId = try appState.nodeService.sendPaymentUsingAmount(invoice: invoice, amountMsat: actualMsat)
        }
        recordPayment(id: "\(paymentId)", type: "lightning", msat: actualMsat, price: price, appState: appState)
        return SendPaymentResult(sentAmountSats: actualMsat / 1000, paymentId: "\(paymentId)", txid: nil)
    }

    private static func sendBolt12(offer: Offer, effectiveSats: UInt64, price: Double,
                                   appState: AppState) async throws -> SendPaymentResult {
        let msat = effectiveSats * 1000
        guard msat > 0 else { throw NSError(
            domain: "Send",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid amount"]
        ) }
        try appState.ensureNoUnsettledSurplus(amountMsat: msat)
        let paymentId = try appState.nodeService.sendBolt12UsingAmount(offer: offer, amountMsat: msat)
        recordPayment(id: "\(paymentId)", type: "bolt12", msat: msat, price: price, appState: appState)
        return SendPaymentResult(sentAmountSats: effectiveSats, paymentId: "\(paymentId)", txid: nil)
    }

    private static func sendLNURL(
        params: LNURLPayParams?,
        comment: String,
        effectiveSats: UInt64,
        price: Double,
        appState: AppState,
        lnurlService: LNURLServiceProtocol
    ) async throws -> SendPaymentResult {
        guard let params else {
            throw NSError(domain: "LNURL", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing LNURL parameters"])
        }
        let msat = effectiveSats * 1000
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let resp = try await lnurlService.fetchInvoice(
            callback: params.callback,
            amountMsat: msat,
            comment: trimmedComment.isEmpty ? nil : trimmedComment
        )
        let bolt11 = try Bolt11Invoice.fromStr(invoiceStr: resp.pr)
        if let invoiceMsat = bolt11.amountMilliSatoshis(), invoiceMsat != msat {
            throw LNURLError.amountOutOfBounds(minSats: params.minSats, maxSats: params.maxSats)
        }
        try appState.ensureNoUnsettledSurplus(amountMsat: msat)
        let paymentId = try appState.nodeService.sendPayment(invoice: bolt11)
        recordPayment(id: "\(paymentId)", type: "lightning", msat: msat, price: price, appState: appState)
        return SendPaymentResult(sentAmountSats: effectiveSats, paymentId: "\(paymentId)", txid: nil)
    }

    static func sendOnchain(
        address: String,
        effectiveSats: UInt64,
        price: Double,
        feeRateSatVb: UInt64?,
        appState: AppState
    ) async throws -> SendPaymentResult {
        guard effectiveSats > 0 else { throw NSError(
            domain: "Send",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Invalid amount"]
        ) }
        if let channel = appState.nodeService.channels.first(where: \.isChannelReady) {
            guard !appState.isSweeping else {
                throw NSError(
                    domain: "Send",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "A splice is already in progress"]
                )
            }
            try appState.beginSpliceOut(amountSats: effectiveSats, address: address)
            do {
                try appState.nodeService.spliceOut(
                    userChannelId: channel.userChannelId,
                    counterpartyNodeId: channel.counterpartyNodeId,
                    address: address,
                    amountSats: effectiveSats
                )
            } catch {
                appState.cancelPendingSpliceStart()
                throw error
            }
            return SendPaymentResult(sentAmountSats: effectiveSats, paymentId: nil, txid: nil)
        } else {
            let txid = try appState.nodeService.sendOnchain(
                address: address,
                amountSats: effectiveSats,
                feeRateSatVb: feeRateSatVb
            )
            appState.onchainSendBroadcasted(amountSats: effectiveSats, isSendAll: false, txid: txid)
            recordPayment(
                id: txid,
                type: "onchain",
                msat: effectiveSats * 1000,
                price: price,
                address: address,
                txid: txid,
                appState: appState
            )
            return SendPaymentResult(sentAmountSats: effectiveSats, paymentId: nil, txid: txid)
        }
    }

    static func sendAllOnchain(
        address: String,
        price: Double,
        feeRateSatVb: UInt64?,
        appState: AppState
    ) async throws -> SendPaymentResult {
        let txid = try appState.nodeService.sendAllOnchain(
            address: address,
            feeRateSatVb: feeRateSatVb
        )
        let onchainSats = appState.onchainBalanceSats
        recordPayment(
            id: txid,
            type: "onchain",
            msat: onchainSats * 1000,
            price: price,
            address: address,
            txid: txid,
            appState: appState
        )
        appState.onchainSendBroadcasted(amountSats: onchainSats, isSendAll: true, txid: txid)
        return SendPaymentResult(sentAmountSats: onchainSats, paymentId: nil, txid: txid)
    }

    private static func recordPayment(
        id: String,
        type: String,
        msat: UInt64,
        price: Double,
        address: String? = nil,
        txid: String? = nil,
        appState: AppState
    ) {
        let usd: Double? = price > 0 ? (Double(msat) / 1000.0 / Double(Constants.satsInBTC)) * price : nil
        _ = try? appState.databaseService?.paymentRepo.recordPayment(
            paymentId: id,
            paymentType: type,
            direction: "sent",
            amountMsat: msat,
            amountUSD: usd,
            btcPrice: price > 0 ? price : nil,
            counterparty: nil,
            status: "pending",
            txid: txid,
            address: address
        )
    }

    enum SettlementOutcome: Sendable {
        case settled(paymentHash: String?)
        case failed(reason: String)
        case timedOut
    }

    static func awaitPaymentSettlement(
        paymentId: String,
        timeoutSeconds: TimeInterval
    ) async -> SettlementOutcome {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            var settledObserver: NSObjectProtocol?
            var failedObserver: NSObjectProtocol?

            let finish: (SettlementOutcome) -> Void = { outcome in
                lock.lock()
                defer { lock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                if let s = settledObserver { NotificationCenter.default.removeObserver(s) }
                if let f = failedObserver { NotificationCenter.default.removeObserver(f) }
                continuation.resume(returning: outcome)
            }

            settledObserver = NotificationCenter.default.addObserver(
                forName: .paymentSettled,
                object: nil,
                queue: .main
            ) { note in
                guard let pid = note.userInfo?["paymentId"] as? String, pid == paymentId else { return }
                let hash = note.userInfo?["paymentHash"] as? String
                finish(.settled(paymentHash: hash))
            }

            failedObserver = NotificationCenter.default.addObserver(
                forName: .paymentFailed,
                object: nil,
                queue: .main
            ) { note in
                guard let pid = note.userInfo?["paymentId"] as? String, pid == paymentId else { return }
                let reason = note.userInfo?["errorMessage"] as? String
                    ?? note.userInfo?["reason"] as? String
                    ?? "The payment did not complete. Check its status in History before trying again."
                finish(.failed(reason: reason))
            }

            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                finish(.timedOut)
            }
        }
    }
}
