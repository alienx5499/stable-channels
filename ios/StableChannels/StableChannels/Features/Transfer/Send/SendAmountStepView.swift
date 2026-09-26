import SwiftUI

/// Step 2: Amount entry, fiat/sat conversions, LNURL constraints, and optional payee comment.
struct SendAmountStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let payeeInfo = model.lnurlParams?.plainTextDescription {
                    payeeMetadataCard(description: payeeInfo)
                }

                heroAmountCard

                presetPercentages

                if let params = model.lnurlParams, let maxComment = params.commentAllowed, maxComment > 0 {
                    commentCard(maxCharacters: maxComment)
                }

                if let error = model.errorMessage {
                    errorCard(error)
                }

                Spacer(minLength: 24)

                continueButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func payeeMetadataCard(description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "header_payee", defaultValue: "Payee"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(description)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var heroAmountCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField("0.00", text: $model.amountUSDStr)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .keyboardType(.decimalPad)
                    .onChange(of: model.amountUSDStr) { _, new in
                        model.amountUSDStr = InputSanitizer.decimal(new)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
            if sats > 0 {
                Text("≈ \(sats.btcSpacedFormatted) BTC (\(sats) sats)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let params = model.lnurlParams, params.hasCustomSendBounds {
                Text("Allowed range: \(params.minSats) – \(params.maxSats) sats")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var presetPercentages: some View {
        HStack(spacing: 12) {
            ForEach([25, 50, 100], id: \.self) { pct in
                Button {
                    applyPercentage(pct)
                } label: {
                    Text(pct == 100 ? "Max" : "\(pct)%")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func commentCard(maxCharacters: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "header_comment", defaultValue: "Note"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.lnurlComment.count)/\(maxCharacters)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TextField(
                String(localized: "placeholder_optional_comment", defaultValue: "Optional note for payee"),
                text: $model.lnurlComment
            )
            .font(.subheadline)
            .onChange(of: model.lnurlComment) { _, new in
                if new.count > maxCharacters {
                    model.lnurlComment = String(new.prefix(maxCharacters))
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func errorCard(_ message: String) -> some View {
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

    private var continueButton: some View {
        Button {
            model.proceedFromAmount(appState: appState)
        } label: {
            Text(String(localized: "button_continue", defaultValue: "Continue"))
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canProceed)
        .padding(.bottom, 16)
    }

    private var canProceed: Bool {
        let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        return sats > 0
    }

    private func applyPercentage(_ percent: Int) {
        let maxSats = appState.totalBalanceSats
        guard maxSats > 0, appState.accountingBTCPrice > 0 else { return }
        let targetSats = (maxSats * UInt64(percent)) / 100
        let usd = (Double(targetSats) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice
        model.amountUSDStr = String(format: "%.2f", usd)
    }
}
