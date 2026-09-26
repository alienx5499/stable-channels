import SwiftUI

/// Main coordinator view for the redesigned Send workflow.
struct SendView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model = SendFlowModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    navLeadingButton
                }
                if model.step == .confirm {
                    ToolbarItem(placement: .primaryAction) {
                        Button(String(localized: "button_add_note", defaultValue: "Add Note")) {
                            // Note placeholder for memo metadata
                        }
                        .foregroundStyle(.cyan)
                    }
                }
            }
            .task {
                model.feeRateSatVb = await appState.feeRateService.currentRate()
            }
        }
    }

    private var navigationTitle: String {
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
