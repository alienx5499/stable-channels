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

/// Formatter that divides an address into 4-character chunks and marks boundary chunks.
/// Helps users easily verify recipient addresses against clipboard hijackers.
enum AddressVisualChunker {
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
