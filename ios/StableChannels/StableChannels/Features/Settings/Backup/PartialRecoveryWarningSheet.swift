import SwiftUI

struct PartialRecoveryWarningSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // Warning Icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 88, height: 88)

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                    }

                    // Title
                    Text("Partial Recovery Warning")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    // Warning Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bolt.slash.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)

                            Text(
                                "This recovery will restore onchain funds but NOT Lightning channel state. Lightning funds will be lost and may require LSP force-close."
                            )
                            .font(.system(size: 15))
                            .foregroundStyle(Color(white: 0.85))
                            .lineSpacing(4)
                        }

                        Divider()
                            .background(Color.white.opacity(0.12))

                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.octagon.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                                .padding(.top, 2)

                            Text(
                                "Please withdraw all BTC before proceeding. Existing wallet data will be completely overwritten."
                            )
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.35))
                            .lineSpacing(4)
                        }
                    }
                    .padding(20)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    Spacer()

                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(role: .destructive) {
                            dismiss()
                            onConfirm()
                        } label: {
                            Text("I Understand, Restore Wallet")
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
                            Text("Cancel")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color(white: 0.7))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
