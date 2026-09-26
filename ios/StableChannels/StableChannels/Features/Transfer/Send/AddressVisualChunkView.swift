import SwiftUI

/// Renders a destination's human-verifiable representation according to its protocol type.
struct AddressVisualChunkView: View {
    let representation: DestinationVisualRepresentation

    var body: some View {
        switch representation {
        case .onchain(let chunked):
            onchainView(chunked)
        case .invoice(let prefix, let middle, let suffix, _):
            invoiceView(prefix: prefix, middle: middle, suffix: suffix)
        case .lightningAddress(let handle, let domain):
            lightningAddressView(handle: handle, domain: domain)
        case .lnurl(let host, _):
            lnurlView(host: host)
        }
    }

    private func onchainView(_ chunked: ChunkedAddress) -> some View {
        Text(chunkedText(for: chunked))
            .font(.system(.subheadline, design: .monospaced))
            .lineSpacing(4)
    }

    private func invoiceView(prefix: String, middle: String, suffix: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
            HStack(spacing: 2) {
                Text(prefix)
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(.primary)
                if !middle.isEmpty {
                    Text(middle)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                Text(suffix)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
    }

    private func lightningAddressView(handle: String, domain: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "at.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(handle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("@\(domain)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(String(localized: "label_lightning_address", defaultValue: "Lightning Address"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func lnurlView(host: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(host)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "label_lnurl_service", defaultValue: "LNURL Service"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chunkedText(for chunked: ChunkedAddress) -> AttributedString {
        var str = AttributedString()
        for (i, chunk) in chunked.chunks.enumerated() {
            var chunkAttr = AttributedString(chunk.text)
            if chunk.isHighlighted {
                chunkAttr.foregroundColor = Color.orange
                chunkAttr.font = .system(.subheadline, design: .monospaced).weight(.semibold)
            } else {
                chunkAttr.foregroundColor = Color(uiColor: .secondaryLabel)
                chunkAttr.font = .system(.subheadline, design: .monospaced)
            }
            str.append(chunkAttr)
            if i < chunked.chunks.count - 1 {
                str.append(AttributedString("  "))
            }
        }
        return str
    }
}
