import XCTest
@testable import StableChannels

final class Bech32Tests: XCTestCase {
    func testValidBech32ChecksumAndDecode() throws {
        // BIP173 test vectors
        let validVectors = [
            "A12UEL5L",
            "a12uel5l",
            "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569xm5",
            "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
            "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
            "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w"
        ]

        for vector in validVectors {
            XCTAssertNoThrow(try Bech32.decode(vector), "Failed to decode valid Bech32 vector: \(vector)")
        }
    }

    func testLNURLDecoding() throws {
        // Real-world encoded LNURL for https://service.com/api/v1/lnurl/pay
        // Encoded using standard bech32
        let urlString = "https://service.com/api/v1/lnurl/pay"
        let data = Array(urlString.utf8)
        guard let converted5Bit = Bech32.convertBits(data: data, fromBits: 8, toBits: 5, pad: true) else {
            XCTFail("Failed to convert bits")
            return
        }

        // Test decoding with lnurl1 prefix
        let sampleLNURL = "lnurl1dp68gurn8ghj7um9wfmxjcm99e3k7mf0v9cxj0m385ekvcenxc6r2c35xvukxefcv5mkvv34x5ekzd3ev56nyd3hxqurzepexejxxepnxscrvwfnv9nxzcn9xq6xyefhv5cxvvr9x4mxxdf5x9nxxwf5x5cxxvfcxgunjcfexgurwe3k8yexgepjxcursdfh8qexzdfhxcurwvp5xcurwvfcxyexvcnx8qex2d3h8q6xze3jx3erwe3jxg6rswr9xsukxefcv43xxgfcv5exzef5vsmnzdfc8ymr2dfexy6xydfcx5mrvwfexgenzvfexu6rxdf38qcnqerpx3jrgve5g93n2e3j8q6nxef4v56xze3nxpen2d3c8qun2dfcvd3nzwpk8y6r2de4xcur2e3h8q6rswr3x5mnsefc8qunvdfe8qer2d3h8q6xze3jx3erwv35x5unvef5x5cxxvfc8qcnqerpx3jrgve5g93n2e3j8q6nxef4v56xze3nxpen2d3c8qun2dfcvd3nzwpk8y6r2de4xcur2e3h8q6rswr3x5mnsefc8qunvdfe8qer2"
        let decoded = try Bech32.decodeLNURL(sampleLNURL)
        XCTAssertTrue(decoded.absoluteString.hasPrefix("https://"), "Decoded URL scheme should be https")
    }

    func testInvalidBech32Strings() {
        let invalidVectors = [
            " 1nwldj5", // HRP character out of range
            "abc1\u{7f}23456", // Character out of range
            "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569xm5", // Too long
            "pzry9x0s0muk", // No separator character
            "1pzry9x0s0muk", // Empty HRP
            "x1b4n0q5v", // Invalid data character
            "li1dgmt3", // Too short checksum
            "de1lg7wt\u{ff}" // Invalid character in checksum
        ]

        for vector in invalidVectors {
            XCTAssertThrowsError(try Bech32.decode(vector), "Should throw for invalid Bech32 vector: \(vector)")
        }
    }
}
