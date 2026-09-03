import SwiftUI

// MARK: - Apple-Grade Partial Recovery Warning Modal (Zero Gradients, Crisp System Typography)

struct PartialRecoveryWarningSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            // Flat System Icon
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 48, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.top, 24)

                            // Title & Overview Subtitle
                            VStack(spacing: 8) {
                                Text(String(
                                    localized: "title_partial_recovery_warning",
                                    defaultValue: "Partial Recovery Warning"
                                ))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                                Text(String(
                                    localized: "desc_partial_recovery_overview",
                                    defaultValue: "Restoring from a seed phrase only recovers onchain funds. Channel state cannot be restored."
                                ))
                                .font(.system(size: 15))
                                .foregroundStyle(Color(uiColor: .lightGray))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 24)
                            }

                            // Structured Information Cards (Flat Inset Grouped Styling)
                            VStack(spacing: 12) {
                                // 1. Lightning Channel State Notice
                                infoCard(
                                    icon: "bolt.slash.fill",
                                    iconColor: .orange,
                                    title: "Lightning Channels Not Recovered",
                                    description: "This recovery will restore onchain funds but NOT Lightning channel state. Lightning funds will be lost and may require LSP force-close."
                                )

                                // 2. Overwrite & Withdrawal Notice
                                infoCard(
                                    icon: "exclamationmark.octagon.fill",
                                    iconColor: Color(red: 1.0, green: 0.35, blue: 0.35),
                                    title: "Existing Data Overwritten",
                                    description: "Please withdraw all BTC before proceeding. Existing wallet data will be completely overwritten."
                                )
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                        }
                        .padding(.bottom, 24)
                    }

                    // Bottom Actions
                    VStack(spacing: 10) {
                        Button(role: .destructive) {
                            dismiss()
                            onConfirm()
                        } label: {
                            Text(String(
                                localized: "button_i_understand_restore",
                                defaultValue: "I Understand, Restore Wallet"
                            ))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.red)
                            .clipShape(Capsule())
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text(String(localized: "button_cancel", defaultValue: "Cancel"))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(white: 0.65))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .background(Color.black.ignoresSafeArea(edges: .bottom))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color(white: 0.35))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Inset Info Card

    private func infoCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(white: 0.72))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
