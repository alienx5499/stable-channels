import SwiftUI

// MARK: - Apple-Grade Partial Recovery Warning Modal

struct PartialRecoveryWarningSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            // Hero Icon & Glow
                            ZStack {
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [Color.orange.opacity(0.25), Color.clear],
                                            center: .center,
                                            startRadius: 10,
                                            endRadius: 55
                                        )
                                    )
                                    .frame(width: 110, height: 110)

                                ZStack {
                                    Circle()
                                        .fill(Color.orange.opacity(0.15))
                                        .frame(width: 72, height: 72)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                                        )

                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 34, weight: .semibold))
                                        .foregroundStyle(.orange)
                                        .shadow(color: .orange.opacity(0.5), radius: 12, x: 0, y: 4)
                                }
                            }
                            .padding(.top, 16)

                            // Title & Subtitle Lockup
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
                                    defaultValue: "Restoring from a seed phrase only recovers onchain Bitcoin. Please review the details below before proceeding."
                                ))
                                .font(.system(size: 14))
                                .foregroundStyle(Color(uiColor: .lightGray))
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .padding(.horizontal, 20)
                            }

                            // Information Cards Stack
                            VStack(spacing: 12) {
                                // 1. Lightning Channel Warning Card
                                infoCard(
                                    icon: "bolt.slash.fill",
                                    iconColor: .orange,
                                    badgeBackground: Color.orange.opacity(0.12),
                                    badgeBorder: Color.orange.opacity(0.25),
                                    title: "Lightning Channels Not Recovered",
                                    description: "This recovery will restore onchain funds but NOT Lightning channel state. Lightning funds will be lost and may require LSP force-close."
                                )

                                // 2. Overwrite & Withdrawal Warning Card
                                infoCard(
                                    icon: "exclamationmark.octagon.fill",
                                    iconColor: Color(red: 1.0, green: 0.35, blue: 0.35),
                                    badgeBackground: Color.red.opacity(0.12),
                                    badgeBorder: Color.red.opacity(0.25),
                                    title: "Existing Data Overwritten",
                                    description: "Please withdraw all BTC before proceeding. Existing wallet data will be completely overwritten."
                                )
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 24)
                    }

                    // Bottom Action Stack
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
                                .font(.system(size: 15, weight: .medium))
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
                            .font(.system(size: 22))
                            .foregroundStyle(Color(white: 0.35))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Card Component

    private func infoCard(
        icon: String,
        iconColor: Color,
        badgeBackground: Color,
        badgeBorder: Color,
        title: String,
        description: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Rounded Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(badgeBackground)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(badgeBorder, lineWidth: 1)
                    )

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            .padding(.top, 2)

            // Text Hierarchy
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
