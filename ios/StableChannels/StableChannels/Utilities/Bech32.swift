import Foundation

/// High-performance, zero-dependency BIP-173 Bech32 and BIP-350 Bech32m decoder.
/// Optimized for low-latency LNURL-pay and Lightning Address resolution.
enum Bech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private static let bech32ChecksumConst: UInt32 = 1
    private static let bech32mChecksumConst: UInt32 = 0x2BC8_30A3

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
        case insecureClearnetScheme

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
            case .insecureClearnetScheme:
                return "LNURL endpoint must use HTTPS for clearnet connections."
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
        for byte in hrp {
            polymodStep(&chk, value: byte >> 5)
        }
        polymodStep(&chk, value: 0)
        for byte in hrp {
            polymodStep(&chk, value: byte & 31)
        }
        for val in data {
            polymodStep(&chk, value: val)
        }
        return chk == bech32ChecksumConst || chk == bech32mChecksumConst
    }

    /// Verifies if a string is a valid Bech32 or Bech32m checksummed string and returns its lowercased HRP.
    static func verifyChecksum(bechString: String) -> String? {
        let trimmed = bechString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }

        var hasLower = false
        var hasUpper = false
        for byte in trimmed.utf8 {
            if byte >= 0x61 && byte <= 0x7A { hasLower = true }
            if byte >= 0x41 && byte <= 0x5A { hasUpper = true }
            if hasLower && hasUpper { return nil }
        }

        let lowercased = trimmed.lowercased()
        guard let pos = lowercased.lastIndex(of: "1") else { return nil }
        let hrp = lowercased[..<pos]
        guard !hrp.isEmpty else { return nil }

        let dataPart = lowercased[lowercased.index(after: pos)...]
        guard dataPart.count >= 6 else { return nil }

        var values = [UInt8]()
        values.reserveCapacity(dataPart.count)

        for char in dataPart {
            guard let asciiVal = char.asciiValue, asciiVal < 128 else { return nil }
            let val = asciiLookupTable[Int(asciiVal)]
            guard val >= 0 else { return nil }
            values.append(UInt8(val))
        }

        guard verifyChecksum(hrp: hrp.utf8, data: values) else { return nil }
        return String(hrp)
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
              let url = URL(string: urlString) else {
            throw Error.invalidUtf8String
        }

        let scheme = url.scheme?.lowercased()
        let isHttps = scheme == "https"
        let isOnionHttp = scheme == "http" && (url.host?.lowercased().hasSuffix(".onion") == true)
        guard isHttps || isOnionHttp else {
            throw Error.insecureClearnetScheme
        }

        return url
    }
}
