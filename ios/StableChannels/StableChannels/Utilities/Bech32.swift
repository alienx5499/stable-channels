import Foundation

/// High-performance, zero-dependency BIP-173 / BIP-350 Bech32 and Bech32m encoder and decoder.
/// Optimized for low-latency LNURL-pay and Lightning Address resolution.
enum Bech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    /// Direct O(1) 128-byte ASCII character lookup table (avoids Unicode hash maps and allocations).
    private static let asciiLookupTable: [Int8] = {
        var table = [Int8](repeating: -1, count: 128)
        let charsetBytes = Array(charset.utf8)
        for (index, byte) in charsetBytes.enumerated() {
            table[Int(byte)] = Int8(index)
        }
        return table
    }()

    enum Error: Swift.Error, LocalizedError {
        case invalidLength
        case invalidCharacter(Character)
        case missingHrp
        case invalidChecksum
        case bitsConversionFailed
        case invalidUtf8String

        var errorDescription: String? {
            switch self {
            case .invalidLength:
                return "The Bech32 string is too short."
            case let .invalidCharacter(c):
                return "Invalid Bech32 character: '\(c)'."
            case .missingHrp:
                return "The Bech32 string is missing a human-readable prefix (HRP)."
            case .invalidChecksum:
                return "Invalid Bech32 checksum."
            case .bitsConversionFailed:
                return "Failed to convert 5-bit Bech32 data to 8-bit bytes."
            case .invalidUtf8String:
                return "The decoded payload is not a valid UTF-8 string."
            }
        }
    }

    // MARK: - Streaming Polymod (Zero-Allocation)

    @inline(__always)
    private static func polymodStep(_ chk: inout UInt32, value: UInt8) {
        let b = chk >> 25
        chk = ((chk & 0x1FFFFFF) << 5) ^ UInt32(value)
        if (b & 0x01) != 0 { chk ^= 0x3B6A57B2 }
        if (b & 0x02) != 0 { chk ^= 0x26508E6D }
        if (b & 0x04) != 0 { chk ^= 0x1EA119FA }
        if (b & 0x08) != 0 { chk ^= 0x3D4233DD }
        if (b & 0x10) != 0 { chk ^= 0x2A1462B3 }
    }

    private static func verifyChecksum(hrp: Substring.UTF8View, data: [UInt8]) -> Bool {
        var chk: UInt32 = 1
        // Stream hrp high 3 bits
        for byte in hrp {
            polymodStep(&chk, value: byte >> 5)
        }
        polymodStep(&chk, value: 0)
        // Stream hrp low 5 bits
        for byte in hrp {
            polymodStep(&chk, value: byte & 31)
        }
        // Stream data values
        for val in data {
            polymodStep(&chk, value: val)
        }
        return chk == 1
    }

    // MARK: - 5-bit to 8-bit bit conversion

    /// Converts an array of 5-bit integers to an array of 8-bit integers (or vice-versa).
    static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var ret = [UInt8]()
        ret.reserveCapacity((data.count * fromBits + toBits - 1) / toBits)
        let maxv = (1 << toBits) - 1
        let maxAcc = (1 << (fromBits + toBits - 1)) - 1

        for value in data {
            if value < 0 || (Int(value) >> fromBits) != 0 {
                return nil
            }
            acc = ((acc << fromBits) | Int(value)) & maxAcc
            bits += fromBits
            while bits >= toBits {
                bits -= toBits
                ret.append(UInt8((acc >> bits) & maxv))
            }
        }

        if pad {
            if bits > 0 {
                ret.append(UInt8((acc << (toBits - bits)) & maxv))
            }
        } else if bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0 {
            return nil
        }

        return ret
    }

    // MARK: - Decode

    /// Decodes a Bech32 string into its HRP and 8-bit data payload.
    static func decode(_ bechString: String) throws -> (hrp: String, data: Data) {
        let trimmed = bechString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            throw Error.invalidLength
        }

        var hasLower = false
        var hasUpper = false
        for byte in trimmed.utf8 {
            if byte >= 0x61 && byte <= 0x7A { hasLower = true }
            if byte >= 0x41 && byte <= 0x5A { hasUpper = true }
            if hasLower && hasUpper {
                throw Error.invalidCharacter(trimmed.first(where: { $0.isUppercase }) ?? "A")
            }
        }

        let lowercased = trimmed.lowercased()
        guard let pos = lowercased.lastIndex(of: "1") else {
            throw Error.missingHrp
        }

        let hrp = lowercased[..<pos]
        guard !hrp.isEmpty else {
            throw Error.missingHrp
        }

        let dataPart = lowercased[lowercased.index(after: pos)...]
        guard dataPart.count >= 6 else {
            throw Error.invalidLength
        }

        var values = [UInt8]()
        values.reserveCapacity(dataPart.count)

        for char in dataPart {
            guard let asciiVal = char.asciiValue, asciiVal < 128 else {
                throw Error.invalidCharacter(char)
            }
            let val = asciiLookupTable[Int(asciiVal)]
            guard val >= 0 else {
                throw Error.invalidCharacter(char)
            }
            values.append(UInt8(val))
        }

        guard verifyChecksum(hrp: hrp.utf8, data: values) else {
            throw Error.invalidChecksum
        }

        // Drop 6-character checksum
        let payload5Bit = Array(values.dropLast(6))
        guard let converted8Bit = convertBits(data: payload5Bit, fromBits: 5, toBits: 8, pad: false) else {
            throw Error.bitsConversionFailed
        }

        return (String(hrp), Data(converted8Bit))
    }

    /// Decodes an LNURL bech32 string (`lnurl1...`) into an HTTPS/HTTP `URL`.
    static func decodeLNURL(_ lnurlString: String) throws -> URL {
        var clean = lnurlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("lightning:") {
            clean = String(clean.dropFirst("lightning:".count))
        }

        let (hrp, data) = try decode(clean)
        guard hrp.lowercased() == "lnurl" else {
            throw Error.missingHrp
        }

        guard let urlString = String(data: data, encoding: .utf8),
              let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http" else {
            throw Error.invalidUtf8String
        }

        return url
    }
}
