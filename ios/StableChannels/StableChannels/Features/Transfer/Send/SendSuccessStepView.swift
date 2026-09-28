import SwiftUI

/// Step 4: Payment completion receipt with transaction ID and dismiss controls.
struct SendSuccessStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 90, height: 90)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 6) {
                Text(verbatim: successTitle)
                    .font(.title2.weight(.bold))

                let sats = model.sentAmountSats
                let usd = (Double(sats) / Double(Constants.satsInBTC)) * appState.btcPrice
                if appState.btcPrice > 0 {
                    Text(usd.usdFormatted)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                Text("\(sats.btcSpacedFormatted) BTC")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if isBolt12 {
                    Text(String(
                        localized: "note_bolt12_asynchronous",
                        defaultValue: "Offer payment dispatched. Your node is requesting an invoice over Lightning onion messaging."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.horizontal, 16)
                }
            }

            if let txid = model.successTxid {
                txidCard(txid: txid)
            } else if let paymentId = model.successPaymentId {
                paymentIdCard(paymentId: paymentId)
            }

            Spacer()

            Button {
                onDismiss()
            } label: {
                Text(String(localized: "button_done", defaultValue: "Done"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color.sendBlue)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func txidCard(txid: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "label_txid", defaultValue: "Transaction ID"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                Text(txid)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = txid
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func paymentIdCard(paymentId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "label_payment_id", defaultValue: "Payment ID"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                Text(paymentId)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = paymentId
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var isBolt12: Bool {
        if case .bolt12 = model.destination { return true }
        return false
    }

    private var successTitle: String {
        isBolt12 ? String(localized: "title_payment_initiated", defaultValue: "Payment Initiated") :
            String(localized: "title_payment_sent", defaultValue: "Payment Sent")
    }
}
