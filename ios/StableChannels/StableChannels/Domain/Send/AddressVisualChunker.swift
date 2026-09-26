import Foundation

/// Value type representing an address chunked for human readability and verification.
struct ChunkedAddress: Equatable, Sendable {
    struct Chunk: Identifiable, Equatable, Sendable {
        let id: Int
        let text: String
        let isHighlighted: Bool
    }

    let chunks: [Chunk]
    let raw: String

    var formattedString: String {
        chunks.map(\.text).joined(separator: "  ")
    }
}

/// Domain representation of how a payment recipient is visually formatted for human verification.
enum DestinationVisualRepresentation: Equatable, Sendable {
    case onchain(ChunkedAddress)
    case invoice(prefix: String, middle: String, suffix: String, raw: String)
    case lightningAddress(handle: String, domain: String)
    case lnurl(host: String, rawUrl: String)

    var rawDestination: String {
        switch self {
        case .onchain(let chunked): return chunked.raw
        case .invoice(_, _, _, let raw): return raw
        case .lightningAddress(let handle, let domain): return "\(handle)@\(domain)"
        case .lnurl(_, let rawUrl): return rawUrl
        }
    }
}

/// Formatter that divides an address into 4-character chunks and marks boundary chunks.
/// Helps users easily verify recipient addresses against clipboard hijackers.
enum AddressVisualChunker {
    static func formatDestination(_ destination: SendDestination) -> DestinationVisualRepresentation {
        switch destination {
        case .onchain(let address):
            return .onchain(chunkAddress(address, chunkSize: 4))
        case .bolt11(_, let raw, _), .bolt12(_, let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 28 else {
                return .invoice(prefix: trimmed, middle: "", suffix: "", raw: trimmed)
            }
            let pIdx = trimmed.index(trimmed.startIndex, offsetBy: 14, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let sIdx = trimmed.index(trimmed.endIndex, offsetBy: -10, limitedBy: trimmed.startIndex) ?? trimmed
                .startIndex
            return .invoice(
                prefix: String(trimmed[..<pIdx]),
                middle: "········",
                suffix: String(trimmed[sIdx...]),
                raw: trimmed
            )
        case .lightningAddress(let handle, let domain, _):
            return .lightningAddress(handle: handle, domain: domain)
        case .lnurlPay(let url):
            return .lnurl(host: url.host ?? url.absoluteString, rawUrl: url.absoluteString)
        }
    }

    static func chunkAddress(_ raw: String, chunkSize: Int = 4) -> ChunkedAddress {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ChunkedAddress(chunks: [], raw: raw)
        }

        var textChunks: [String] = []
        var currentIndex = trimmed.startIndex

        while currentIndex < trimmed.endIndex {
            let nextIndex = trimmed.index(currentIndex, offsetBy: chunkSize, limitedBy: trimmed.endIndex) ?? trimmed
                .endIndex
            textChunks.append(String(trimmed[currentIndex..<nextIndex]))
            currentIndex = nextIndex
        }

        let total = textChunks.count
        var resultChunks: [ChunkedAddress.Chunk] = []
        resultChunks.reserveCapacity(total)

        for (index, chunkText) in textChunks.enumerated() {
            let isHighlighted: Bool
            if total <= 3 {
                isHighlighted = (index == 0 || index == total - 1)
            } else {
                // Highlight first 2 chunks and last 2 chunks
                isHighlighted = (index < 2 || index >= total - 2)
            }
            resultChunks.append(ChunkedAddress.Chunk(id: index, text: chunkText, isHighlighted: isHighlighted))
        }

        return ChunkedAddress(chunks: resultChunks, raw: trimmed)
    }
}
