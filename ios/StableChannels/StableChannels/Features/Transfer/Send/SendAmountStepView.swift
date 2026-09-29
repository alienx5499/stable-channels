import SwiftUI

/// Step 2: Amount entry, fiat/sat conversions, LNURL constraints, and optional payee comment.
struct SendAmountStepView: View {
    @Bindable var model: SendFlowModel
    @Environment(AppState.self) private var appState
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
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
            .frame(maxWidth: .infinity)
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
        let isInsufficient = sats > available || (available == 0 && sats > 0)
        let usd = (Double(available) / Double(Constants.satsInBTC)) * appState.accountingBTCPrice

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "label_available_balance", defaultValue: "Available:"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(usd.usdFormatted) (\(available.btcSpacedFormatted) BTC)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isInsufficient && sats > 0 ? Color.red : Color.secondary)
                Spacer()
            }

            if isInsufficient && sats > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text(String(localized: "error_amount_exceeds_balance", defaultValue: "Amount exceeds your balance"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.2), value: isInsufficient)
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

            let displayText = model.amountInputText.isEmpty ? model.amountUnit.placeholder : model.amountInputText
            let fieldWidth = min(CGFloat(displayText.count) * 19.0 + 20.0, 240.0)

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
                .multilineTextAlignment(model.amountUnit == .usd ? .leading : .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: fieldWidth)
                .focused($isAmountFocused)
                .onChange(of: model.amountInputText) { _, new in
                    let sanitized = InputSanitizer.decimal(new, maxDecimals: model.amountUnit.maxDecimals)
                    if sanitized.count > 16 {
                        model.amountInputText = String(sanitized.prefix(16))
                    } else {
                        model.amountInputText = sanitized
                    }
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
        let fee = model.estimatedFeeSats(appState: appState)
        let maxSpendable = available > fee ? (available - fee) : available
        let currentSats = model.computeEffectiveSats(btcPrice: appState.accountingBTCPrice)
        let isMax = available > 0 && (currentSats == maxSpendable || currentSats == available)
        return HStack(spacing: 12) {
            ForEach([25, 50, 100], id: \.self) { pct in
                Button {
                    model.applyPercentage(
                        pct,
                        totalBalanceSats: available,
                        btcPrice: appState.accountingBTCPrice,
                        appState: appState
                    )
                } label: {
                    if pct == 100 {
                        HStack(spacing: 5) {
                            LemniscateBloomIcon(isActive: isMax, size: 13, tint: Color.sendBlue)
                            Text(String(localized: "button_max", defaultValue: "Max"))
                                .font(.subheadline.weight(.medium))
                        }
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
            isAmountFocused = false
            UIApplication.shared.sendAction(
                Selector(("resignFirstResponder")),
                to: nil,
                from: nil,
                for: nil
            )
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
