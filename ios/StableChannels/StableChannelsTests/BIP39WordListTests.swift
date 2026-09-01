import Foundation
@testable import StableChannels
import XCTest

final class BIP39WordListTests: XCTestCase {
    func testWordList_contains2048Words() {
        XCTAssertEqual(BIP39WordList.english.count, 2048)
        XCTAssertEqual(BIP39WordList.english.first, "abandon")
        XCTAssertEqual(BIP39WordList.english.last, "zoo")
    }

    func testIsValidWord_validAndInvalid() {
        XCTAssertTrue(BIP39WordList.isValidWord("abandon"))
        XCTAssertTrue(BIP39WordList.isValidWord("ABANDON"))
        XCTAssertTrue(BIP39WordList.isValidWord("  zoo  "))
        XCTAssertTrue(BIP39WordList.isValidWord("satoshi"))

        XCTAssertFalse(BIP39WordList.isValidWord("notabipword"))
        XCTAssertFalse(BIP39WordList.isValidWord(""))
        XCTAssertFalse(BIP39WordList.isValidWord("123"))
    }

    func testHasPrefixMatch_validAndInvalid() {
        XCTAssertTrue(BIP39WordList.hasPrefixMatch("ab"))
        XCTAssertTrue(BIP39WordList.hasPrefixMatch("z"))
        XCTAssertTrue(BIP39WordList.hasPrefixMatch("sato"))

        XCTAssertFalse(BIP39WordList.hasPrefixMatch("nb"))
        XCTAssertFalse(BIP39WordList.hasPrefixMatch("zzzz"))
        XCTAssertFalse(BIP39WordList.hasPrefixMatch("12"))
    }

    func testSuggestions_returnsMatchingPrefixesUpToLimit() {
        let suggestionsN = BIP39WordList.suggestions(for: "n", limit: 4)
        XCTAssertEqual(suggestionsN.count, 4)
        XCTAssertTrue(suggestionsN.allSatisfy { $0.hasPrefix("n") })
        XCTAssertEqual(suggestionsN, ["naive", "name", "napkin", "narrow"])

        let suggestionsEmpty = BIP39WordList.suggestions(for: "")
        XCTAssertTrue(suggestionsEmpty.isEmpty)

        let suggestionsInvalid = BIP39WordList.suggestions(for: "nb")
        XCTAssertTrue(suggestionsInvalid.isEmpty)
    }

    func testIsValidMnemonic_validChecksumAndInvalidChecksum() {
        // Valid 12-word standard test vector
        let valid12 = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
        XCTAssertTrue(BIP39.isValid(valid12))
        XCTAssertTrue(MnemonicUtils.isValidMnemonic(valid12))

        // Valid 24-word standard test vector
        let valid24 = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art"
        XCTAssertTrue(BIP39.isValid(valid24))
        XCTAssertTrue(MnemonicUtils.isValidMnemonic(valid24))

        // Invalid checksum from random 12 BIP-39 words
        let invalidChecksum = "hold nominee jaguar jaguar hair habit gadget fabric keen labor face jealous"
        XCTAssertFalse(BIP39.isValid(invalidChecksum))
        XCTAssertFalse(MnemonicUtils.isValidMnemonic(invalidChecksum))

        // Invalid word count
        let tooFew = "abandon abandon abandon"
        XCTAssertFalse(BIP39.isValid(tooFew))

        // Non-BIP39 word
        let nonBIPWord = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon foobar"
        XCTAssertFalse(BIP39.isValid(nonBIPWord))
    }
}
