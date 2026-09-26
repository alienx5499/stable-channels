import SwiftUI

/// Step 1: Destination input, native toolbar QR/Photo scanning, and subtle protocol recognition.
struct SendRecipientStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 16) {
            recipientCard

            if let error = model.errorMessage {
                errorBanner(error)
            } else {
                destinationFeedback
            }

            availableBalanceFooter

            Spacer(minLength: 20)

            continueButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .qrInputToolbar(text: $model.inputText, sanitize: QRCodeExtractor.sanitizePaymentInput)
    }

    private var recipientCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "header_recipient", defaultValue: "To"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                TextField(
                    String(
                        localized: "placeholder_send_destination",
                        defaultValue: "Address, invoice, or name@domain.com"
                    ),
                    text: $model.inputText,
                    axis: .vertical
                )
                .font(.system(.body, design: .monospaced))
                .lineLimit(3...5)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                if !model.inputText.isEmpty {
                    Button {
                        model.inputText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Divider()

            Button {
                if let clipboard = UIPasteboard.general.string {
                    model.inputText = QRCodeExtractor.sanitizePaymentInput(clipboard)
                }
            } label: {
                Label(String(localized: "button_paste", defaultValue: "Paste"), systemImage: "doc.on.clipboard")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var destinationFeedback: some View {
        switch model.classification {
        case .valid(let target):
            HStack(spacing: 6) {
                Image(systemName: destinationIcon(for: target))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(target.displayTitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        case .invalid(let reason):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 4)
        case .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private var availableBalanceFooter: some View {
        if appState.btcPrice > 0 {
            let usd = Double(appState.totalBalanceSats) / Double(Constants.satsInBTC) * appState.btcPrice
            Text("Available balance: \(usd.usdFormatted)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
    }

    private var continueButton: some View {
        Button {
            Task { await model.proceedFromRecipient(appState: appState) }
        } label: {
            Text(String(localized: "button_continue", defaultValue: "Continue"))
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.destination == nil || model.isFetchingLNURL)
        .padding(.bottom, 16)
    }

    private func destinationIcon(for target: SendDestination) -> String {
        switch target {
        case .bolt11: return "bolt.fill"
        case .bolt12: return "sparkles"
        case .lightningAddress: return "at"
        case .lnurlPay: return "link"
        case .onchain: return "bitcoinsign"
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
            Spacer()
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
