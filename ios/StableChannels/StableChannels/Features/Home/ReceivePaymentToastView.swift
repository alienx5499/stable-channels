import SwiftUI

struct ReceiveEvent: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let amountUSD: Double?
    let amountSats: UInt64
    let type: String // "lightning", "onchain", "stability"
}

struct ReceivePaymentToastView: View {
    let event: ReceiveEvent
    let onDismiss: () -> Void

    @State private var animateIcon = false
    @State private var ringPulse = false

    var body: some View {
        HStack(spacing: 14) {
            // Icon with glowing animated ring
            ZStack {
                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 3)
                    .scaleEffect(ringPulse ? 1.3 : 1.0)
                    .opacity(ringPulse ? 0.0 : 0.8)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: ringPulse)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, Color(red: 0.1, green: 0.8, blue: 0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)

                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(animateIcon ? 1.15 : 0.9)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(badgeLabel)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .foregroundStyle(badgeColor)
                        .clipShape(Capsule())
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let usd = event.amountUSD {
                        Text("+\(usd.usdFormatted)")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, Color(red: 0.2, green: 0.9, blue: 0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Text("(\(event.amountSats.btcSpacedFormatted) BTC)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("+\(event.amountSats.btcSpacedFormatted) BTC")
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, Color(red: 0.2, green: 0.9, blue: 0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.green.opacity(0.5), Color.green.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
        }
        .padding(.horizontal, 16)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                animateIcon = true
            }
            ringPulse = true
        }
    }

    private var iconName: String {
        switch event.type {
        case "onchain":
            return "arrow.down.left.circle.fill"
        case "stability":
            return "shield.fill"
        default:
            return "bolt.fill"
        }
    }

    private var badgeLabel: String {
        switch event.type {
        case "onchain":
            return "On-Chain"
        case "stability":
            return "Stability"
        default:
            return "Lightning"
        }
    }

    private var badgeColor: Color {
        switch event.type {
        case "onchain":
            return .orange
        case "stability":
            return .purple
        default:
            return .green
        }
    }
}
