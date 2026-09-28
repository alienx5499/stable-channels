import SwiftUI
import UIKit

struct OnChainSendView: View {
    @Environment(AppState.self) private var appState
    @State private var address = ""
    @State private var amountUSDStr = ""
    @State private var sendAll = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var txid: String?
    @State private var spliceSuccess = false
    @State private var feeRateSatVb: UInt64?
    @State private var selectedFeeTier: NetworkFeeSpeedTier = .standard
    @State private var showReview = false
    @State private var hasCopiedAddress = false
    @State private var reviewErrorMessage: String?

    private var effectiveFeeRateSatVb: UInt64 {
        let base = feeRateSatVb ?? 10
        return selectedFeeTier.effectiveRate(baseRate: base)
    }

    private var amountSats: UInt64? {
        convertedSats(price: appState.accountingBTCPrice)
    }

    private func convertedSats(price: Double) -> UInt64? {
        guard let usd = Double(amountUSDStr), usd > 0, price > 0 else { return nil }
        let sats = usd / price * Double(Constants.satsInBTC)
        guard sats.isFinite, sats >= 1, sats < Double(UInt64.max) else { return nil }
        return UInt64(sats)
    }

    private var hasReadyChannel: Bool {
        appState.nodeService.channels.contains { $0.isChannelReady }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    addressCard
                    amountCard
                    if hasReadyChannel {
                        infoCard(
                            icon: "arrow.up.arrow.down",
                            text: String(
                                localized: "info_splice_out_funds",
                                defaultValue: "Funds will be sent via splice-out from your Lightning channel."
                            )
                        )
                    }
                    if let txid {
                        successCard(
                            icon: "checkmark.circle.fill",
                            title: String(localized: "success_sent", defaultValue: "Sent!"),
                            detail: String(localized: "label_txid", defaultValue: "TXID") + ": " + txid,
                            monospaced: true,
                            linkStyle: true
                        )
                    }
                    if spliceSuccess {
                        successCard(
                            icon: "checkmark.circle.fill",
                            title: String(localized: "success_splice_out", defaultValue: "Splice-out initiated!"),
                            detail: String(
                                localized: "info_funds_arrive_onchain",
                                defaultValue: "Funds will arrive onchain after confirmation."
                            ),
                            monospaced: false
                        )
                    }
                    if let error = errorMessage {
                        errorCard(error)
                    }
                    sendButton
                    Spacer(minLength: 12)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "title_send_on_chain", defaultValue: "Send Onchain"))
            .navigationBarTitleDisplayMode(.inline)
            .qrInputToolbar(text: $address, sanitize: QRCodeExtractor.sanitizeAddress)
            .sheet(isPresented: $showReview) {
                reviewSheet
            }
            .task {
                feeRateSatVb = await appState.feeRateService.currentRate()
            }
        }
    }

    private var addressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "wallet.bifold")
                    .foregroundStyle(.secondary)
                Text(String(localized: "header_destination_address", defaultValue: "Destination Address"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TextField(String(localized: "placeholder_address", defaultValue: "bc1..."), text: $address)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .onChange(of: address) { _, new in
                    address = QRCodeExtractor.sanitizeAddress(new)
                }
        }
        .padding(16)
        .glassCard()
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(.secondary)
                Text(String(localized: "header_amount", defaultValue: "Amount"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            let available = hasReadyChannel && !appState.isSweeping ? appState.totalBalanceSats : appState
                .spendableOnchainSats
            let availableUSD = appState
                .accountingBTCPrice > 0 ? (Double(available) / Double(Constants.satsInBTC)) * appState
                .accountingBTCPrice : 0

            if sendAll {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(localized: "label_dollar_sign", defaultValue: "$"))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(verbatim: String(format: "%.2f", availableUSD))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if available > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .foregroundStyle(.primary)
                        Text("\(available.btcSpacedFormatted) BTC")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(localized: "label_dollar_sign", defaultValue: "$"))
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField(
                        String(localized: "placeholder_amount_usd", defaultValue: "0.00"),
                        text: $amountUSDStr
                    )
                    .keyboardType(.decimalPad)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .onChange(of: amountUSDStr) { _, new in
                        let sanitized = InputSanitizer.decimal(new)
                        amountUSDStr = sanitized.count > 16 ? String(sanitized.prefix(16)) : sanitized
                    }
                }
                let isExceeded = (amountSats ?? 0) > available
                if let sats = amountSats, sats > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "bitcoinsign.circle.fill")
                            .foregroundStyle(.primary)
                        Text("\(sats.btcSpacedFormatted) BTC")
                            .font(.subheadline.weight(.medium))
                            .contentTransition(.numericText())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .animation(.snappy, value: sats)
                }
                if isExceeded {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text(String(
                            localized: "error_amount_exceeds_balance",
                            defaultValue: "Amount exceeds your balance"
                        ))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                    }
                    .transition(.opacity)
                }
            }

            Toggle(isOn: $sendAll) {
                HStack(spacing: 8) {
                    LemniscateBloomIcon(isActive: sendAll, size: 16, tint: .green)
                    Text(String(localized: "toggle_send_all", defaultValue: "Send All"))
                        .font(.subheadline)
                }
            }
            .tint(.green)
        }
        .padding(16)
        .glassCard()
    }

    private func infoCard(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func successCard(icon: String, title: String, detail: String, monospaced: Bool,
                             linkStyle: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if linkStyle {
                    Text(makeTxidAttributed(label: "TXID: ", txid: detail.replacingOccurrences(of: "TXID: ", with: "")))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    Text(detail)
                        .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.green.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.red.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.red.opacity(0.3), lineWidth: 1)
        )
    }

    private var sendButton: some View {
        Button {
            openReview()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.body.weight(.semibold))
                Text(String(localized: "button_send_payment", defaultValue: "Send"))
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .disabled(address.isEmpty || (!sendAll && (amountSats ?? 0) == 0) || isSending)
        .scaleEffect(isSending ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSending)
        .animation(.easeInOut(duration: 0.2), value: address.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: amountSats)
    }

    private func openReview() {
        UIApplication.shared.sendAction(
            Selector(("resignFirstResponder")),
            to: nil,
            from: nil,
            for: nil
        )
        errorMessage = nil
        reviewErrorMessage = nil

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "error_empty_address", defaultValue: "Please enter a destination address.")
            return
        }
        if !sendAll && (amountSats ?? 0) == 0 {
            errorMessage = String(
                localized: "error_invalid_amount",
                defaultValue: "Please enter an amount greater than 0."
            )
            return
        }
        showReview = true
    }

    private var reviewSheet: some View {
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
                        Task { await executeSendFromReview() }
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
                        showReview = false
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

    private func makeTxidAttributed(label: String, txid: String) -> AttributedString {
        var s = AttributedString(label)
        s.foregroundColor = .secondary
        var t = AttributedString(txid)
        t.foregroundColor = .blue
        t.underlineStyle = .single
        t.link = Constants.txExplorerLink(for: txid)
        return s + t
    }

    private func executeSendFromReview() async {
        // Dismiss any active keyboard to avoid blocking system auth dialogs
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
        } else if let price = conversionPrice, let converted = convertedSats(price: price) {
            sats = converted
        } else {
            reviewErrorMessage = String(
                localized: "error_price_unavailable",
                defaultValue: "The BTC price is unavailable or stale. Refresh and try again."
            )
            return
        }

        do {
            // If channel exists, route through splice-out
            if let channel = appState.nodeService.channels.first(where: { $0.isChannelReady }), !sendAll {
                guard !appState.isSweeping else {
                    throw NSError(
                        domain: "",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: String(
                            localized: "error_splice_in_progress",
                            defaultValue: "A splice is already in progress — try again shortly"
                        )]
                    )
                }
                try appState.beginSpliceOut(amountSats: sats, address: address)
                do {
                    try appState.nodeService.spliceOut(
                        userChannelId: channel.userChannelId,
                        counterpartyNodeId: channel.counterpartyNodeId,
                        address: address,
                        amountSats: sats
                    )
                } catch {
                    appState.cancelPendingSpliceStart()
                    throw error
                }
                spliceSuccess = true
                showReview = false
            } else if sendAll {
                let result = try appState.nodeService.sendAllOnchain(
                    address: address,
                    feeRateSatVb: effectiveFeeRateSatVb
                )
                txid = result
                let price = appState.btcPrice
                let onchainSats = appState.onchainBalanceSats
                _ = try? appState.databaseService?.paymentRepo.recordPayment(
                    paymentId: result,
                    paymentType: "onchain",
                    direction: "sent",
                    amountMsat: onchainSats * 1000,
                    amountUSD: price > 0 ? Double(onchainSats) / Double(Constants.satsInBTC) * price : nil,
                    btcPrice: price > 0 ? price : nil,
                    counterparty: nil,
                    status: "pending",
                    txid: result,
                    address: address
                )
                appState.onchainSendBroadcasted(amountSats: onchainSats, isSendAll: true, txid: result)
                showReview = false
            } else {
                let result = try appState.nodeService.sendOnchain(
                    address: address,
                    amountSats: sats,
                    feeRateSatVb: effectiveFeeRateSatVb
                )
                txid = result
                let price = conversionPrice ?? 0
                _ = try? appState.databaseService?.paymentRepo.recordPayment(
                    paymentId: result,
                    paymentType: "onchain",
                    direction: "sent",
                    amountMsat: sats * 1000,
                    amountUSD: price > 0 ? Double(sats) / Double(Constants.satsInBTC) * price : nil,
                    btcPrice: price > 0 ? price : nil,
                    counterparty: nil,
                    status: "pending",
                    txid: result,
                    address: address
                )
                appState.onchainSendBroadcasted(amountSats: sats, isSendAll: false, txid: result)
                showReview = false
            }
        } catch {
            reviewErrorMessage = error.localizedDescription
        }
    }
}

private struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private extension View {
    func glassCard() -> some View { modifier(GlassCardModifier()) }
}
