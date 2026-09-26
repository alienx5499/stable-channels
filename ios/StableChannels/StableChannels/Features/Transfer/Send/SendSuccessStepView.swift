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
                Text(String(localized: "title_payment_sent", defaultValue: "Payment Sent"))
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
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14))
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
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
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
                        .foregroundStyle(.cyan)
                }
            }
        }
        .padding(14)
        .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
