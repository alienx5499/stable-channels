import Foundation
import SwiftUI
import LDKNode

/// State and business orchestration for the Send workflow.
@Observable
@MainActor
final class SendFlowModel {
    var step: SendFlowStep = .recipient
    var inputText: String = "" {
        didSet { onInputChanged() }
    }

    var destination: SendDestination?
    var classification: PaymentDestinationClassification = .empty
    var amountUnit: SendAmountUnit = .usd
    var amountInputText: String = ""

    var lnurlParams: LNURLPayParams?
    var lnurlComment: String = ""
    var isFetchingLNURL: Bool = false
    var isSending: Bool = false
    var errorMessage: String?
    var successPaymentId: String?
    var successTxid: String?
    var sentAmountSats: UInt64 = 0
    var feeRateSatVb: UInt64?
    var selectedFeeTier: NetworkFeeSpeedTier = .standard

    var effectiveFeeRateSatVb: UInt64 {
        let base = feeRateSatVb ?? 10
        return selectedFeeTier.effectiveRate(baseRate: base)
    }

    let lnurlService: LNURLServiceProtocol

    init(lnurlService: LNURLServiceProtocol = LNURLService()) {
        self.lnurlService = lnurlService
    }

    func onInputChanged() {
        errorMessage = nil
        classification = PaymentDestinationClassifier.classify(inputText)
        switch classification {
        case .valid(let target):
            destination = target
        case .invalid, .empty:
            destination = nil
            lnurlParams = nil
        }
    }

    func proceedFromRecipient(appState: AppState) async {
        guard let dest = destination else { return }
        errorMessage = nil

        switch dest {
        case .lightningAddress(_, _, let url), .lnurlPay(let url):
            isFetchingLNURL = true
            defer { isFetchingLNURL = false }
            do {
                let params = try await lnurlService.fetchPayParams(from: url)
                self.lnurlParams = params
                self.step = .amount
            } catch {
                errorMessage = WalletErrorMessages.operation(error, fallback: error.localizedDescription)
            }
        case .bolt11(_, _, let msat):
            if let msat, msat > 0 {
                let requiredSats = msat / 1000
                let available = availableSpendableSats(appState: appState)
                if requiredSats > available || available == 0 {
                    errorMessage = "Amount exceeds your balance for this invoice. Available: \(available.btcSpacedFormatted) BTC"
                    return
                }
                self.step = .confirm
            } else {
                self.step = .amount
            }
        case .bolt12, .onchain:
            self.step = .amount
        }
    }

    func availableSpendableSats(appState: AppState) -> UInt64 {
        guard let dest = destination else { return appState.totalBalanceSats }
        switch dest {
        case .bolt11, .bolt12, .lightningAddress, .lnurlPay:
            let readyChannels = appState.nodeService.channels.filter(\.isChannelReady)
            if !readyChannels.isEmpty {
                let channelOutbound = readyChannels.map(\.outboundCapacityMsat).reduce(0, +) / 1000
                return min(channelOutbound, appState.lightningBalanceSats)
            } else {
                return appState.lightningBalanceSats
            }
        case .onchain:
            if appState.hasReadyChannel && !appState.isSweeping {
                return appState.totalBalanceSats
            } else {
                return appState.spendableOnchainSats
            }
        }
    }

    func estimatedFeeSats(appState: AppState) -> UInt64 {
        let sats = computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        switch destination {
        case .bolt11, .bolt12, .lightningAddress, .lnurlPay:
            let base = UInt64(Constants.lightningDefaultForwardingFeeBaseMsat)
            let prop = UInt64(Constants.lightningDefaultForwardingFeeProportionalMillionths)
            return PaymentFeeEstimator.estimateLightningFee(sats: sats, baseMsat: base, proportionalMillionths: prop)
        case .onchain:
            return PaymentFeeEstimator.estimateOnchainFee(
                feeRateSatVb: effectiveFeeRateSatVb,
                isSendAll: false
            )
        case .none:
            return 0
        }
    }

    func isInsufficientBalance(appState: AppState) -> Bool {
        let sats = computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        let totalDebit = sats + estimatedFeeSats(appState: appState)
        let available = availableSpendableSats(appState: appState)
        return totalDebit > available || available == 0
    }

    func proceedFromAmount(appState: AppState) {
        normalizeAmountInput()
        errorMessage = nil

        let available = availableSpendableSats(appState: appState)
        guard available > 0 else {
            errorMessage = "Insufficient balance. Your available balance is 0 sats."
            return
        }

        let sats = computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        guard sats > 0 else {
            errorMessage = "Please enter an amount greater than 0."
            return
        }

        if let params = lnurlParams {
            if sats < params.minSats || sats > params.maxSats {
                errorMessage = "Amount must be between \(params.minSats) and \(params.maxSats) sats."
                return
            }
        }

        guard sats <= available else {
            let price = appState.accountingBTCPrice
            let availableUSD = price > 0 ? (Double(available) / Double(Constants.satsInBTC)) * price : 0
            if amountUnit == .usd && price > 0 {
                errorMessage = "Amount exceeds your balance. Available: $\(String(format: "%.2f", availableUSD)) (\(available.btcSpacedFormatted) BTC)"
            } else {
                errorMessage = "Amount exceeds your balance. Available: \(available.btcSpacedFormatted) BTC"
            }
            return
        }

        self.step = .confirm
    }

    func normalizeAmountInput() {
        guard !amountInputText.isEmpty else { return }
        switch amountUnit {
        case .usd:
            if let val = Double(amountInputText) { amountInputText = val > 0 ? String(format: "%.2f", val) : "" }
        case .sats:
            if let sats = UInt64(amountInputText) { amountInputText = sats > 0 ? "\(sats)" : "" }
        case .btc:
            if let btc = Double(amountInputText), btc > 0 {
                var trimmed = String(format: "%.8f", btc)
                while trimmed.hasSuffix("0") && trimmed.contains(".") {
                    trimmed.removeLast()
                }
                if trimmed.hasSuffix(".") { trimmed.removeLast() }
                amountInputText = trimmed
            }
        }
    }

    func computeEffectiveSats(btcPrice: Double) -> UInt64 {
        if let dest = destination, case .bolt11(_, _, let msat) = dest, let msat, msat > 0 { return msat / 1000 }
        guard let val = Double(amountInputText), val > 0 else { return 0 }
        switch amountUnit {
        case .sats:
            return (val.isFinite && val >= 1 && val < Double(UInt64.max)) ? UInt64(val) : 0
        case .usd:
            guard btcPrice > 0 else { return 0 }
            let sats = (val / btcPrice) * Double(Constants.satsInBTC)
            return (sats.isFinite && sats >= 1 && sats < Double(UInt64.max)) ? UInt64(sats) : 0
        case .btc:
            let sats = val * Double(Constants.satsInBTC)
            return (sats.isFinite && sats >= 0.5 && sats < Double(UInt64.max)) ? UInt64(round(sats)) : 0
        }
    }

    func switchUnit(to newUnit: SendAmountUnit, btcPrice: Double) {
        guard newUnit != amountUnit else { return }
        let sats = computeEffectiveSats(btcPrice: btcPrice)
        amountUnit = newUnit
        guard sats > 0 else {
            amountInputText = ""
            return
        }
        switch newUnit {
        case .usd:
            let usd = (Double(sats) / Double(Constants.satsInBTC)) * btcPrice
            amountInputText = String(format: "%.2f", usd)
        case .sats:
            amountInputText = "\(sats)"
        case .btc:
            let btc = Double(sats) / Double(Constants.satsInBTC)
            amountInputText = String(format: "%.8f", btc)
        }
    }

    func applyPercentage(_ percent: Int, totalBalanceSats: UInt64, btcPrice: Double) {
        guard totalBalanceSats > 0, btcPrice > 0 else { return }
        let targetSats = (totalBalanceSats * UInt64(percent)) / 100
        switch amountUnit {
        case .usd:
            let usd = (Double(targetSats) / Double(Constants.satsInBTC)) * btcPrice
            amountInputText = String(format: "%.2f", usd)
        case .sats:
            amountInputText = "\(targetSats)"
        case .btc:
            let btc = Double(targetSats) / Double(Constants.satsInBTC)
            amountInputText = String(format: "%.8f", btc)
        }
    }

    func executeSend(appState: AppState) async {
        guard let dest = destination else { return }
        errorMessage = nil
        isSending = true
        defer { isSending = false }

        let authReason = "Confirm payment to \(dest.displayTitle)"
        let authEnabled = UserDefaults.standard.bool(forKey: "transactionAuthEnabled")
        if authEnabled {
            let passed = await appState.authenticate(reason: authReason)
            guard passed else {
                errorMessage = appState.authError ?? "Authentication required to send."
                return
            }
        }

        appState.ensureLSPConnected()
        let sats = computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        guard sats > 0 else {
            errorMessage = "Invalid amount."
            return
        }
        let available = availableSpendableSats(appState: appState)
        let totalDebit = sats + estimatedFeeSats(appState: appState)
        guard totalDebit <= available, available > 0 else {
            errorMessage = "Amount exceeds your balance. Available: \(available.btcSpacedFormatted) BTC"
            return
        }

        do {
            let result = try await SendPaymentExecutor.execute(
                destination: dest,
                effectiveSats: sats,
                feeRateSatVb: effectiveFeeRateSatVb,
                lnurlParams: lnurlParams,
                lnurlComment: lnurlComment,
                appState: appState,
                lnurlService: lnurlService
            )

            // Onchain broadcasts immediately into mempool
            if let txid = result.txid {
                sentAmountSats = result.sentAmountSats
                successTxid = txid
                successPaymentId = result.paymentId
                step = .success
                return
            }

            // Lightning settlement pipeline (BOLT11, BOLT12, LNURL)
            if let pid = result.paymentId {
                let timeout: TimeInterval
                switch dest {
                case .bolt12:
                    timeout = 10.0
                case .bolt11, .lightningAddress, .lnurlPay:
                    timeout = 7.0
                case .onchain:
                    timeout = 0
                }

                let outcome = await awaitPaymentSettlement(paymentId: pid, timeoutSeconds: timeout)
                switch outcome {
                case .settled:
                    sentAmountSats = result.sentAmountSats
                    successPaymentId = pid
                    successTxid = nil
                    step = .success
                case .failed(let reason):
                    errorMessage = reason
                case .timedOut:
                    sentAmountSats = result.sentAmountSats
                    successPaymentId = pid
                    successTxid = nil
                    step = .success
                }
            }
        } catch {
            errorMessage = WalletErrorMessages.operation(error, fallback: error.localizedDescription)
        }
    }

    private enum PaymentSettlementOutcome: Sendable {
        case settled(paymentHash: String?)
        case failed(reason: String)
        case timedOut
    }

    private func awaitPaymentSettlement(
        paymentId: String,
        timeoutSeconds: TimeInterval
    ) async -> PaymentSettlementOutcome {
        await withCheckedContinuation { continuation in
            let lock = NSLock()
            var hasResumed = false

            var settledObserver: NSObjectProtocol?
            var failedObserver: NSObjectProtocol?

            let finish: (PaymentSettlementOutcome) -> Void = { outcome in
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
