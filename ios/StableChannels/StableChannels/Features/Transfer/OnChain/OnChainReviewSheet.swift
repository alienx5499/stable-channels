import SwiftUI
import UIKit

/// Standalone review and confirmation sheet for onchain sends.
struct OnChainReviewSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let address: String
    let amountUSDStr: String
    let sendAll: Bool
    let amountSats: UInt64?
    let feeRateSatVb: UInt64?
    @Binding var selectedFeeTier: NetworkFeeSpeedTier
    var onSent: (_ txid: String?, _ isSplice: Bool) -> Void

    @State private var isSending = false
    @State private var hasCopiedAddress = false
    @State private var reviewErrorMessage: String?

    private var effectiveFeeRateSatVb: UInt64 {
        let base = feeRateSatVb ?? 10
        return selectedFeeTier.effectiveRate(baseRate: base)
    }

    private var hasReadyChannel: Bool {
        appState.nodeService.channels.contains { $0.isChannelReady }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        reviewAssetCard
                        reviewAddressCard
                        reviewRecipientReceivesCard
                        NetworkFeeSelectorView(
                            selectedTier: $selectedFeeTier,
                            baseFeeRateSatVb: feeRateSatVb ?? 10,
                            isSendAll: sendAll,
                            btcPrice: appState.accountingBTCPrice,
                            showExplanation: false
                        )
                        reviewFeeAndTotalCard

                        if let error = reviewErrorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(12)
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)

                VStack(spacing: 4) {
                    SlideToSendButton(
                        title: String(localized: "button_slide_to_send", defaultValue: "Slide to Send"),
                        isSending: isSending
                    ) {
                        Task { await executeSend() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "title_confirm_transaction", defaultValue: "Confirm transaction"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "button_cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                    .disabled(isSending)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var reviewAssetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "header_account_asset", defaultValue: "Asset & Network"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.orange).frame(width: 36, height: 36)
                    Image(systemName: "bitcoinsign").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "label_bitcoin", defaultValue: "Bitcoin"))
                        .font(.headline)
                    Text(verbatim: hasReadyChannel && !sendAll ? "Onchain • Splice-Out" : "Onchain • Standard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var reviewAddressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "header_address", defaultValue: "Recipient Address"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasCopiedAddress {
                    Text(String(localized: "label_copied", defaultValue: "Copied"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                AddressVisualChunkView(representation: .onchain(AddressVisualChunker.chunkAddress(address)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onTapGesture { copyAddress() }
        }
    }

    private func copyAddress() {
        guard !address.isEmpty else { return }
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.2)) { hasCopiedAddress = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { hasCopiedAddress = false }
        }
    }

    private var reviewRecipientReceivesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "header_recipient_receives", defaultValue: "Recipient Receives"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                if sendAll {
                    let fee = PaymentFeeEstimator.estimateOnchainFee(
                        feeRateSatVb: effectiveFeeRateSatVb,
                        isSendAll: true
                    )
                    let bal = appState.onchainBalanceSats
                    let netSats = bal > fee ? bal - fee : 0
                    let usd = (Double(netSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
                    Text(verbatim: "\(usd.usdFormatted) USD")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(verbatim: "\(netSats.btcSpacedFormatted) BTC")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let sats = amountSats {
                    let usd = (Double(sats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
                    Text(verbatim: "\(usd.usdFormatted) USD")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(verbatim: "\(sats.btcSpacedFormatted) BTC")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var reviewFeeAndTotalCard: some View {
        let effectiveRate = effectiveFeeRateSatVb
        let feeSats = PaymentFeeEstimator.estimateOnchainFee(feeRateSatVb: effectiveRate, isSendAll: sendAll)
        let baseSats = sendAll ? (appState.onchainBalanceSats > feeSats ? appState.onchainBalanceSats - feeSats : 0) :
            (amountSats ?? 0)
        let totalSats = sendAll ? appState.onchainBalanceSats : (baseSats + feeSats)

        let feeUSD = (Double(feeSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
        let totalUSD = (Double(totalSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice

        return VStack(spacing: 10) {
            HStack {
                Text(verbatim: "Network Fee (\(effectiveRate) sat/vB)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "≈ \(feeUSD.usdFormatted) USD").font(.subheadline.weight(.medium))
                    Text(verbatim: "\(feeSats.btcSpacedFormatted) BTC").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text(String(localized: "label_total_spent", defaultValue: "Total Debit")).font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: "≈ \(totalUSD.usdFormatted) USD").font(.headline)
                    Text(verbatim: "\(totalSats.btcSpacedFormatted) BTC").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func executeSend() async {
        UIApplication.shared.sendAction(
            Selector(("resignFirstResponder")),
            to: nil,
            from: nil,
            for: nil
        )

        let transactionAuth = UserDefaults.standard.bool(forKey: "transactionAuthEnabled")
        if transactionAuth {
            let authReason = sendAll ? "Confirm onchain withdrawal" : "Confirm onchain send"
            let authPassed = await appState.authenticate(reason: authReason)
            guard authPassed else {
                reviewErrorMessage = appState.authError ?? "Authentication required to send."
                return
            }
        }

        isSending = true
        reviewErrorMessage = nil
        defer { isSending = false }

        let conversionPrice = sendAll ? nil : appState.accountingBTCPrice
        let sats: UInt64
        if sendAll {
            sats = 0
        } else if let price = conversionPrice, let converted = amountSats {
            sats = converted
        } else {
            reviewErrorMessage = String(
                localized: "error_price_unavailable",
                defaultValue: "The BTC price is unavailable or stale. Refresh and try again."
            )
            return
        }

        do {
            if sendAll {
                let result = try await SendPaymentExecutor.sendAllOnchain(
                    address: address,
                    price: appState.btcPrice,
                    feeRateSatVb: effectiveFeeRateSatVb,
                    appState: appState
                )
                onSent(result.txid, false)
                dismiss()
            } else {
                let result = try await SendPaymentExecutor.sendOnchain(
                    address: address,
                    effectiveSats: sats,
                    price: conversionPrice ?? 0,
                    feeRateSatVb: effectiveFeeRateSatVb,
                    appState: appState
                )
                if result.txid != nil {
                    onSent(result.txid, false)
                } else {
                    onSent(nil, true)
                }
                dismiss()
            }
        } catch {
            reviewErrorMessage = error.localizedDescription
        }
    }
}
