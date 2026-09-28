import SwiftUI

/// Step 2: Amount entry, fiat/sat conversions, LNURL constraints, and optional payee comment.
struct SendAmountStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let payeeInfo = model.lnurlParams?.plainTextDescription {
                    payeeMetadataCard(description: payeeInfo)
                }
                heroAmountCard
                availableBalanceCard
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
        .onAppear { isAmountFocused = true }
        .onChange(of: isAmountFocused) { _, isFocused in
            if !isFocused { model.normalizeAmountInput() }
        }
    }

    private var availableBalanceCard: some View {
        let available = model.availableSpendableSats(appState: appState)
        let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        let isInsufficient = sats > available || available == 0
        let usd = (Double(available) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice

        return HStack {
            Text(String(localized: "label_available_balance", defaultValue: "Available:"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(usd.usdFormatted) (\(available.btcSpacedFormatted) BTC)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isInsufficient && sats > 0 ? Color.red : Color.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var heroAmountCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text(String(localized: "header_amount", defaultValue: "Amount"))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                unitMenuButton
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if model.amountUnit == .usd {
                    Text(verbatim: "$")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                TextField(
                    model.amountInputText.isEmpty ? model.amountUnit.placeholder : "",
                    text: $model.amountInputText
                )
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .keyboardType(model.amountUnit == .sats ? .numberPad : .decimalPad)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: true, vertical: false)
                .focused($isAmountFocused)
                .onChange(of: model.amountInputText) { _, new in
                    model.amountInputText = InputSanitizer.decimal(new, maxDecimals: model.amountUnit.maxDecimals)
                }
                if model.amountUnit != .usd {
                    Text(model.amountUnit.symbolOrSuffix)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture { isAmountFocused = true }

            let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
            if sats > 0 {
                secondaryConversionButton(sats: sats)
            }

            if let params = model.lnurlParams, params.hasCustomSendBounds {
                Text(model.amountUnit.allowedRangeText(params: params, btcPrice: appState.accountingBTCPrice))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var unitMenuButton: some View {
        Menu {
            ForEach(SendAmountUnit.allCases) { unit in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.switchUnit(to: unit, btcPrice: appState.accountingBTCPrice)
                } label: {
                    Text(unit.menuTitle)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.amountUnit.title).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
            .foregroundStyle(.primary)
        }
    }

    private func secondaryConversionButton(sats: UInt64) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            let nextUnit: SendAmountUnit = model.amountUnit == .usd ? .sats : .usd
            model.switchUnit(to: nextUnit, btcPrice: appState.accountingBTCPrice)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down").font(.caption2.weight(.semibold))
                Text(model.amountUnit.secondaryConversionText(sats: sats, btcPrice: appState.accountingBTCPrice))
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }
        .buttonStyle(.plain)
    }

    private func payeeMetadataCard(description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "header_payee", defaultValue: "Payee"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(description).font(.subheadline.weight(.medium)).lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var presetPercentages: some View {
        let available = model.availableSpendableSats(appState: appState)
        return HStack(spacing: 12) {
            ForEach([25, 50, 100], id: \.self) { pct in
                Button {
                    model.applyPercentage(
                        pct,
                        totalBalanceSats: available,
                        btcPrice: appState.accountingBTCPrice
                    )
                } label: {
                    if pct == 100 {
                        Text(String(localized: "button_max", defaultValue: "Max"))
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(verbatim: "\(pct)%")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(available == 0)
            }
        }
    }

    private func commentCard(maxCharacters: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "header_comment", defaultValue: "Note"))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text("\(model.lnurlComment.count)/\(maxCharacters)").font(.caption2).foregroundStyle(.secondary)
            }
            TextField(
                String(localized: "placeholder_optional_comment", defaultValue: "Optional note for payee"),
                text: $model.lnurlComment
            )
            .font(.subheadline)
            .onChange(of: model.lnurlComment) { _, new in
                if new.count > maxCharacters { model.lnurlComment = String(new.prefix(maxCharacters)) }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            Text(message).font(.footnote).foregroundStyle(.red)
            Spacer()
        }
        .padding(12).background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }

    private var continueButton: some View {
        let sats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        let available = model.availableSpendableSats(appState: appState)
        let isBlocked = sats == 0 || sats > available || available == 0

        return Button {
            model.proceedFromAmount(appState: appState)
        } label: {
            Text(String(localized: "button_continue", defaultValue: "Continue"))
                .font(.headline).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Color.sendBlue)
        .disabled(isBlocked)
        .padding(.bottom, 16)
    }
}
