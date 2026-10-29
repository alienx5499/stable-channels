import SwiftUI

/// Offers a newer App Store release on Home until the user updates or dismisses it.
struct HomeUpdateAvailableView: View {
    let release: StoreRelease
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.app.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "update_available_title", defaultValue: "Update available"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(String(
                    localized: "update_available_subtitle",
                    defaultValue: "Version \(release.version.description) is ready to install."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "button_update", defaultValue: "Update")) {
                UIApplication.shared.open(release.url)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(String(localized: "button_dismiss_update", defaultValue: "Dismiss"))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HomeUpdateAvailableView(
        release: StoreRelease(version: AppVersion("0.9.3")!, url: URL(string: "https://apps.apple.com")!),
        onDismiss: {}
    )
    .padding()
}
