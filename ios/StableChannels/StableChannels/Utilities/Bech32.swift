import Foundation

/// BIP-173 / BIP-350 compliant Bech32 and Bech32m encoder and decoder.
/// Used for decoding LNURL-pay strings (LUD-01).
enum Bech32 {
    private static let charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    private static let charsetMap: [Character: UInt8] = {
        var map = [Character: UInt8]()
        for (i, char) in charset.enumerated() {
            map[char] = UInt8(i)
        }
        return map
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

    // MARK: - Polymod Checksum

    private static func polymod(_ values: [UInt8]) -> UInt32 {
        var chk: UInt32 = 1
        let generator: [UInt32] = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
        for v in values {
            let b = chk >> 25
            chk = ((chk & 0x1FFFFFF) << 5) ^ UInt32(v)
            for i in 0..<5 {
                if ((b >> i) & 1) != 0 {
                    chk ^= generator[i]
                }
            }
        }
        return chk
    }

    private static func hrpExpand(_ hrp: String) -> [UInt8] {
        var ret = [UInt8]()
        let scalars = hrp.unicodeScalars
        for scalar in scalars {
            ret.append(UInt8(scalar.value >> 5))
        }
        ret.append(0)
        for scalar in scalars {
            ret.append(UInt8(scalar.value & 31))
        }
        return ret
    }

    private static func verifyChecksum(hrp: String, data: [UInt8]) -> Bool {
        polymod(hrpExpand(hrp) + data) == 1
    }

    // MARK: - 5-bit to 8-bit bit conversion

    /// Converts an array of 5-bit integers to an array of 8-bit integers (or vice-versa).
    static func convertBits(data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [UInt8]? {
        var acc = 0
        var bits = 0
        var ret = [UInt8]()
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

        let isLower = trimmed.lowercased() == trimmed
        let isUpper = trimmed.uppercased() == trimmed
        guard isLower || isUpper else {
            throw Error.invalidCharacter(trimmed.first(where: { $0.isUppercase }) ?? "A")
        }

        let str = trimmed.lowercased()
        guard let pos = str.lastIndex(of: "1") else {
            throw Error.missingHrp
        }

        let hrp = String(str[..<pos])
        guard !hrp.isEmpty else {
            throw Error.missingHrp
        }

        let dataPart = str[str.index(after: pos)...]
        guard dataPart.count >= 6 else {
            throw Error.invalidLength
        }

        var values = [UInt8]()
        for c in dataPart {
            guard let val = charsetMap[c] else {
                throw Error.invalidCharacter(c)
            }
            values.append(val)
        }

        guard verifyChecksum(hrp: hrp, data: values) else {
            throw Error.invalidChecksum
        }

        // Drop 6-character checksum
        let payload5Bit = Array(values.dropLast(6))
        guard let converted8Bit = convertBits(data: payload5Bit, fromBits: 5, toBits: 8, pad: false) else {
            throw Error.bitsConversionFailed
        }

        return (hrp, Data(converted8Bit))
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
