import SwiftUI

/// Visual badge showing real-time destination recognition and protocol type.
struct SendDestinationBadgeView: View {
    let classification: PaymentDestinationClassification

    var body: some View {
        switch classification {
        case .valid(let target):
            HStack(spacing: 8) {
                Image(systemName: badgeIcon(for: target))
                    .foregroundStyle(badgeColor(for: target))
                Text(target.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(badgeColor(for: target).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        case .invalid(let reason):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(12)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        case .empty:
            EmptyView()
        }
    }

    private func badgeIcon(for target: SendDestination) -> String {
        switch target {
        case .bolt11: return "bolt.fill"
        case .bolt12: return "sparkles"
        case .lightningAddress: return "at"
        case .lnurlPay: return "link.circle.fill"
        case .onchain: return "bitcoinsign.circle.fill"
        }
    }

    private func badgeColor(for target: SendDestination) -> Color {
        switch target {
        case .bolt11, .lightningAddress: return .cyan
        case .bolt12, .lnurlPay: return .purple
        case .onchain: return .orange
        }
    }
}
