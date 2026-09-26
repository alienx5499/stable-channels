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
    var amountUSDStr: String = ""
    var isSatPrimary: Bool = false
    var lnurlParams: LNURLPayParams?
    var lnurlComment: String = ""
    var isFetchingLNURL: Bool = false
    var isSending: Bool = false
    var errorMessage: String?
    var successPaymentId: String?
    var successTxid: String?
    var sentAmountSats: UInt64 = 0
    var feeRateSatVb: UInt64?

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

    func proceedFromRecipient(appState _: AppState) async {
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
            self.step = (msat != nil && msat! > 0) ? .confirm : .amount
        case .bolt12, .onchain:
            self.step = .amount
        }
    }

    func proceedFromAmount(appState: AppState) {
        errorMessage = nil
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

        self.step = .confirm
    }

    func computeEffectiveSats(btcPrice: Double) -> UInt64 {
        if let dest = destination, case .bolt11(_, _, let msat) = dest, let msat, msat > 0 {
            return msat / 1000
        }
        guard btcPrice > 0, let usd = Double(amountUSDStr), usd > 0 else { return 0 }
        let sats = (usd / btcPrice) * Double(Constants.satsInBTC)
        guard sats.isFinite, sats >= 1, sats < Double(UInt64.max) else { return 0 }
        return UInt64(sats)
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

        do {
            let result = try await SendPaymentExecutor.execute(
                destination: dest,
                effectiveSats: sats,
                lnurlParams: lnurlParams,
                lnurlComment: lnurlComment,
                appState: appState,
                lnurlService: lnurlService
            )
            sentAmountSats = result.sentAmountSats
            successPaymentId = result.paymentId
            successTxid = result.txid
            step = .success
        } catch {
            errorMessage = WalletErrorMessages.operation(error, fallback: error.localizedDescription)
        }
    }
}
