import SwiftUI

/// Main coordinator view for the redesigned Send workflow.
struct SendView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model = SendFlowModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if model.isFetchingLNURL {
                    SendLoadingView(
                        title: String(localized: "title_verifying_payment", defaultValue: "Verifying Destination"),
                        subtitle: String(
                            localized: "subtitle_resolving_lnurl",
                            defaultValue: "Connecting to Lightning service..."
                        ),
                        curve: .roseCurve,
                        tint: Color.sendBlue
                    )
                    .transition(.opacity)
                } else if model.isSending {
                    SendLoadingView(
                        title: String(localized: "title_sending_payment", defaultValue: "Sending Payment"),
                        subtitle: String(
                            localized: "subtitle_broadcasting_tx",
                            defaultValue: "Validating invoice and broadcasting..."
                        ),
                        curve: .roseCurve,
                        tint: Color.sendBlue
                    )
                    .transition(.opacity)
                } else {
                    Group {
                        switch model.step {
                        case .recipient:
                            SendRecipientStepView(model: model)
                        case .amount:
                            SendAmountStepView(model: model)
                        case .confirm:
                            SendConfirmStepView(model: model)
                        case .success:
                            SendSuccessStepView(model: model) {
                                dismiss()
                            }
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.isFetchingLNURL)
            .animation(.easeInOut(duration: 0.25), value: model.isSending)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.step)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    navLeadingButton
                }
            }
            .task {
                model.feeRateSatVb = await appState.feeRateService.currentRate()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var navigationTitle: String {
        if model.isFetchingLNURL || model.isSending {
            return ""
        }
        switch model.step {
        case .recipient:
            return String(localized: "title_send", defaultValue: "Send")
        case .amount:
            return String(localized: "title_amount", defaultValue: "Amount")
        case .confirm:
            return String(localized: "title_confirm_transaction", defaultValue: "Confirm transaction")
        case .success:
            return ""
        }
    }

    @ViewBuilder
    private var navLeadingButton: some View {
        if model.isFetchingLNURL || model.isSending {
            EmptyView()
        } else {
            switch model.step {
            case .recipient:
                Button(String(localized: "button_cancel", defaultValue: "Cancel")) {
                    dismiss()
                }
            case .amount:
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        model.step = .recipient
                    }
                } label: {
                    Label(String(localized: "button_back", defaultValue: "Back"), systemImage: "chevron.left")
                }
            case .confirm:
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if let dest = model.destination, dest.requiresManualAmount {
                            model.step = .amount
                        } else {
                            model.step = .recipient
                        }
                    }
                } label: {
                    Label(String(localized: "button_back", defaultValue: "Back"), systemImage: "chevron.left")
                }
            case .success:
                EmptyView()
            }
        }
    }
}
