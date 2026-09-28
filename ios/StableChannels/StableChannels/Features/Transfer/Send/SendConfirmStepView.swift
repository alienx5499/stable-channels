import SwiftUI

/// Step 3: Transaction review with visual address chunking and Slide to Send confirmation.
struct SendConfirmStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState
    @State private var hasCopiedAddress = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountAssetCard
                addressCard
                recipientReceivesCard

                if case .onchain = model.destination {
                    NetworkFeeSelectorView(
                        selectedTier: $model.selectedFeeTier,
                        baseFeeRateSatVb: model.feeRateSatVb ?? 10,
                        isSendAll: false,
                        btcPrice: appState.accountingBTCPrice
                    )
                }

                feeAndTotalCard

                if let error = model.errorMessage {
                    errorBanner(error)
                }

                Spacer(minLength: 16)

                SlideToSendButton(
                    title: String(localized: "button_slide_to_send", defaultValue: "Slide to Send"),
                    isSending: model.isSending
                ) {
                    Task { await model.executeSend(appState: appState) }
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private var accountAssetCard: some View {
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
                    Text(verbatim: sourceRouteDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var sourceRouteDescription: String {
        switch model.destination {
        case .bolt11:
            return "Lightning (BOLT11) • Instant"
        case .bolt12:
            return "Lightning (BOLT12) • Instant"
        case .lightningAddress, .lnurlPay:
            return "Lightning • Instant"
        case .onchain:
            let isReady = appState.nodeService.channels.contains(where: \.isChannelReady)
            return isReady ? "Onchain • Splice-Out" : "Onchain • Standard"
        case .none:
            return "Standard"
        }
    }

    private var addressHeaderTitle: String {
        switch model.destination {
        case .bolt11: return String(localized: "header_invoice", defaultValue: "Lightning (BOLT11) Invoice")
        case .bolt12: return String(localized: "header_offer", defaultValue: "Lightning (BOLT12) Offer")
        case .lightningAddress, .lnurlPay: return String(localized: "header_recipient", defaultValue: "Recipient")
        case .onchain, .none: return String(localized: "header_address", defaultValue: "Recipient Address")
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(addressHeaderTitle)
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
                if let dest = model.destination {
                    AddressVisualChunkView(representation: AddressVisualChunker.formatDestination(dest))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onTapGesture { copyAddress() }
        }
    }

    private func copyAddress() {
        guard let raw = model.destination?.rawDestination else { return }
        UIPasteboard.general.string = raw
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.2)) { hasCopiedAddress = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { hasCopiedAddress = false }
        }
    }

    private var recipientReceivesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "header_recipient_receives", defaultValue: "Recipient Receives"))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
                let usd = (Double(sats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
                Text("\(usd.usdFormatted) USD")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(sats.btcSpacedFormatted) BTC")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var feeLabelText: String {
        switch model.destination {
        case .bolt11, .bolt12, .lightningAddress, .lnurlPay:
            return String(localized: "label_routing_fee", defaultValue: "Routing Fee (Lightning)")
        case .onchain:
            return "Network Fee (\(model.effectiveFeeRateSatVb) sat/vB)"
        case .none:
            return String(localized: "label_total_fees", defaultValue: "Network Fee")
        }
    }

    private var feeAndTotalCard: some View {
        let feeSats = estimatedFeeSats
        let totalSats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice) + feeSats
        let feeUSD = (Double(feeSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
        let totalUSD = (Double(totalSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice

        return VStack(spacing: 10) {
            HStack {
                Text(feeLabelText)
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

    private var estimatedFeeSats: UInt64 {
        let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        switch model.destination {
        case .bolt11, .bolt12, .lightningAddress, .lnurlPay:
            let base = UInt64(Constants.lightningDefaultForwardingFeeBaseMsat)
            let prop = UInt64(Constants.lightningDefaultForwardingFeeProportionalMillionths)
            return PaymentFeeEstimator.estimateLightningFee(sats: sats, baseMsat: base, proportionalMillionths: prop)
        case .onchain:
            return PaymentFeeEstimator.estimateOnchainFee(
                feeRateSatVb: model.effectiveFeeRateSatVb,
                isSendAll: false
            )
        case .none: return 0
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(message).font(.footnote).foregroundStyle(.red)
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
