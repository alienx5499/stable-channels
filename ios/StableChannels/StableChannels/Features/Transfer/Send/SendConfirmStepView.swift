import SwiftUI

/// Step 3: Transaction review with visual address chunking and Slide to Send confirmation.
struct SendConfirmStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    SendConfirmAssetCard(routeDescription: sourceRouteDescription)

                    if let dest = model.destination {
                        SendConfirmAddressCard(
                            headerTitle: addressHeaderTitle,
                            representation: AddressVisualChunker.formatDestination(dest),
                            rawAddress: dest.rawDestination
                        )
                    }

                    let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
                    SendConfirmReceivesCard(
                        amountSats: sats,
                        btcPrice: appState.accountingBTCPrice
                    )

                    if case .onchain = model.destination, !isSpliceOut {
                        NetworkFeeSelectorView(
                            selectedTier: $model.selectedFeeTier,
                            baseFeeRateSatVb: model.feeRateSatVb ?? 10,
                            isSendAll: false,
                            btcPrice: appState.accountingBTCPrice,
                            showExplanation: false
                        )
                    }

                    SendConfirmFeeTotalCard(
                        estimatedFeeSats: model.estimatedFeeSats(appState: appState),
                        totalDebitSats: sats + model.estimatedFeeSats(appState: appState),
                        btcPrice: appState.accountingBTCPrice
                    )

                    if isInsufficientBalance {
                        errorBanner(String(
                            localized: "error_insufficient_balance_total",
                            defaultValue: "Insufficient balance. Total debit exceeds available funds."
                        ))
                    } else if let error = model.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 4) {
                SlideToSendButton(
                    title: String(localized: "button_slide_to_send", defaultValue: "Slide to Send"),
                    sendingTitle: sendingStatusText,
                    isSending: model.isSending
                ) {
                    Task { await model.executeSend(appState: appState) }
                }
                .disabled(isInsufficientBalance)
                .opacity(isInsufficientBalance ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .onAppear {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
            )
        }
    }

    private var isSpliceOut: Bool {
        appState.hasReadyChannel && !appState.isSweeping
    }

    private var isInsufficientBalance: Bool {
        model.isInsufficientBalance(appState: appState)
    }

    private var sendingStatusText: String {
        switch model.destination {
        case .bolt12:
            return String(localized: "status_requesting_invoice", defaultValue: "Requesting Invoice...")
        case .bolt11, .lightningAddress, .lnurlPay:
            return String(localized: "status_routing_payment", defaultValue: "Routing Payment...")
        case .onchain, .none:
            return String(localized: "status_broadcasting", defaultValue: "Broadcasting...")
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
            return isSpliceOut ? "Onchain • Splice-Out" : "Onchain • Standard"
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
