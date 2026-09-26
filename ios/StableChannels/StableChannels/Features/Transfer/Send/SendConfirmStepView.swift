import SwiftUI

/// Step 3: Transaction review with visual address chunking and Slide to Send confirmation.
struct SendConfirmStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                accountAssetCard

                addressCard

                recipientReceivesCard

                feeAndTotalCard

                if let error = model.errorMessage {
                    errorBanner(error)
                }

                Spacer(minLength: 16)

                SlideToSendButton(
                    title: String(localized: "button_slide_to_send", defaultValue: "Slide to Send"),
                    isSending: model.isSending,
                    onConfirmed: {
                        Task { await model.executeSend(appState: appState) }
                    }
                )
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    private var accountAssetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "header_account_asset", defaultValue: "Account & Asset"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 40, height: 40)
                    Image(systemName: "bitcoinsign")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "label_bitcoin", defaultValue: "Bitcoin"))
                        .font(.headline)
                    Text(sourceRouteDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var sourceRouteDescription: String {
        switch model.destination {
        case .bolt11, .bolt12, .lightningAddress, .lnurlPay:
            return "LIGHTNING • INSTANT"
        case .onchain:
            let isReady = appState.nodeService.channels.contains(where: \.isChannelReady)
            return isReady ? "ONCHAIN • SPLICE-OUT" : "ONCHAIN • STANDARD"
        case .none:
            return "STANDARD"
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "header_address", defaultValue: "Address"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                if let dest = model.destination {
                    let chunked = AddressVisualChunker.chunkAddress(dest.rawDestination)
                    AddressVisualChunkView(chunked: chunked)
                }

                HStack {
                    Spacer()
                    Button {
                        if let raw = model.destination?.rawDestination {
                            UIPasteboard.general.string = raw
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    } label: {
                        Label(String(localized: "button_copy", defaultValue: "Copy"), systemImage: "doc.on.doc")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.cyan)
                    }
                }
            }
            .padding(14)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var recipientReceivesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "header_recipient_receives", defaultValue: "Recipient Receives"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
                let usd = (Double(sats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
                Text("\(usd.usdFormatted) USD")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("\(sats.btcSpacedFormatted) BTC")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var feeAndTotalCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text(String(localized: "label_total_fees", defaultValue: "Total Fees"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                let feeSats = estimatedFeeSats
                let feeUSD = (Double(feeSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
                VStack(alignment: .trailing, spacing: 2) {
                    Text("≈ \(feeUSD.usdFormatted) USD")
                        .font(.subheadline.weight(.medium))
                    Text("\(feeSats.btcSpacedFormatted) BTC")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            HStack {
                Text(String(localized: "label_total_spent", defaultValue: "Total Spent"))
                    .font(.headline)
                Spacer()
                let totalSats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice) + estimatedFeeSats
                let totalUSD = (Double(totalSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
                VStack(alignment: .trailing, spacing: 2) {
                    Text("≈ \(totalUSD.usdFormatted) USD")
                        .font(.headline)
                    Text("\(totalSats.btcSpacedFormatted) BTC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private var estimatedFeeSats: UInt64 {
        let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        switch model.destination {
        case .bolt11, .bolt12, .lightningAddress, .lnurlPay:
            let base = UInt64(Constants.lightningDefaultForwardingFeeBaseMsat)
            let prop = UInt64(Constants.lightningDefaultForwardingFeeProportionalMillionths)
            return PaymentFeeEstimator.estimateLightningFee(sats: sats, baseMsat: base, proportionalMillionths: prop)
        case .onchain:
            let rate = model.feeRateSatVb ?? 10
            return PaymentFeeEstimator.estimateOnchainFee(feeRateSatVb: rate, isSendAll: false)
        case .none:
            return 0
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
