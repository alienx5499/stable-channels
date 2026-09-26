import SwiftUI

/// Renders a chunked address with colored boundary highlights for anti-phishing visual verification.
struct AddressVisualChunkView: View {
    let chunked: ChunkedAddress

    var body: some View {
        Text(chunkedText)
            .font(.system(.subheadline, design: .monospaced))
            .lineSpacing(4)
    }

    private var chunkedText: AttributedString {
        var str = AttributedString()
        for (i, chunk) in chunked.chunks.enumerated() {
            var chunkAttr = AttributedString(chunk.text)
            if chunk.isHighlighted {
                chunkAttr.foregroundColor = .cyan
            } else {
                chunkAttr.foregroundColor = Color(white: 0.8)
            }
            str.append(chunkAttr)
            if i < chunked.chunks.count - 1 {
                str.append(AttributedString("  "))
            }
        }
        return str
    }
}
