import XCTest
import LDKNode
@testable import StableChannels

final class AddressVisualChunkerTests: XCTestCase {
    func testChunkingStandardAddress() {
        let addr = "bc1plvty62zgr8ae8vat0xyqrae0qgnlmcra5nnhpamhn46kdjuwh43q0wes3n"
        let result = AddressVisualChunker.chunkAddress(addr, chunkSize: 4)

        XCTAssertFalse(result.chunks.isEmpty)
        XCTAssertEqual(result.chunks[0].text, "bc1p")
        XCTAssertEqual(result.chunks[1].text, "lvty")
        XCTAssertTrue(result.chunks[0].isHighlighted)
        XCTAssertTrue(result.chunks[1].isHighlighted)

        // Middle chunks should not be highlighted
        XCTAssertFalse(result.chunks[2].isHighlighted)

        // Last 2 chunks should be highlighted
        let total = result.chunks.count
        XCTAssertTrue(result.chunks[total - 1].isHighlighted)
        XCTAssertTrue(result.chunks[total - 2].isHighlighted)
    }

    func testChunkingShortAddress() {
        let shortAddr = "1A1zP1eP"
        let result = AddressVisualChunker.chunkAddress(shortAddr, chunkSize: 4)

        XCTAssertEqual(result.chunks.count, 2)
        XCTAssertEqual(result.chunks[0].text, "1A1z")
        XCTAssertEqual(result.chunks[1].text, "P1eP")
        XCTAssertTrue(result.chunks[0].isHighlighted)
        XCTAssertTrue(result.chunks[1].isHighlighted)
    }

    func testEmptyAddress() {
        let result = AddressVisualChunker.chunkAddress("")
        XCTAssertTrue(result.chunks.isEmpty)
        XCTAssertEqual(result.formattedString, "")
    }

    func testFormatDestinationOnchain() {
        let addr = "bc1plvty62zgr8ae8vat0xyqrae0qgnlmcra5nnhpamhn46kdjuwh43q0wes3n"
        let dest = SendDestination.onchain(address: addr)
        let rep = AddressVisualChunker.formatDestination(dest)

        guard case .onchain(let chunked) = rep else {
            XCTFail("Expected .onchain representation")
            return
        }
        XCTAssertEqual(chunked.raw, addr)
        XCTAssertEqual(chunked.chunks[0].text, "bc1p")
        XCTAssertTrue(chunked.chunks[0].isHighlighted)
        XCTAssertTrue(chunked.chunks[1].isHighlighted)
    }

    func testFormatDestinationLightningAddressDoesNotChunk() throws {
        let url = try XCTUnwrap(URL(string: "https://0xprabal.com/.well-known/lnurlp/prabal"))
        let dest = SendDestination.lightningAddress(handle: "prabal", domain: "0xprabal.com", url: url)
        let rep = AddressVisualChunker.formatDestination(dest)

        guard case .lightningAddress(let handle, let domain) = rep else {
            XCTFail("Expected .lightningAddress representation without chunking")
            return
        }
        XCTAssertEqual(handle, "prabal")
        XCTAssertEqual(domain, "0xprabal.com")
        XCTAssertEqual(rep.rawDestination, "prabal@0xprabal.com")
    }

    func testFormatDestinationLNURLPayDoesNotChunk() throws {
        let url = try XCTUnwrap(URL(string: "https://ln.tips/service"))
        let dest = SendDestination.lnurlPay(url: url)
        let rep = AddressVisualChunker.formatDestination(dest)

        guard case .lnurl(let host, let rawUrl) = rep else {
            XCTFail("Expected .lnurl representation without chunking")
            return
        }
        XCTAssertEqual(host, "ln.tips")
        XCTAssertEqual(rawUrl, "https://ln.tips/service")
    }

    func testFormatDestinationInvoiceHighlightsBoundaries() {
        let rawInvoice = "lnbc1pn8g249pp5f6ytj32ty90jhvw69enf30hwfgdhyymjewywcmfjevflg6s4z86qdqqcqzzgxqyz5vqrzjqwnvuc0u4txn35cafc7w94gxvq5p3cu9dd95f7hlrh0fvs46wpvhdfjjzh2j9f7ye5qqqqryqqqqthqqpysp5mm832athgcal3m7h35sc29j63lmgzvwc5smfjh2es65elc2ns7dq9qrsgqu2xcje2gsnjp0wn97aknyd3h58an7sjj6nhcrm40846jxphv47958c6th76whmec8ttr2wmg6sxwchvxmsc00kqrzqcga6lvsf9jtqgqy5yexa"
        guard let invoice = try? Bolt11Invoice.fromStr(invoiceStr: rawInvoice) else {
            XCTFail("Failed to parse valid bolt11 test invoice")
            return
        }
        let dest = SendDestination.bolt11(invoice: invoice, raw: rawInvoice, amountMsat: 10_000_000)
        let rep = AddressVisualChunker.formatDestination(dest)

        guard case .invoice(let prefix, let middle, let suffix, let raw) = rep else {
            XCTFail("Expected .invoice representation")
            return
        }
        XCTAssertEqual(raw, rawInvoice)
        XCTAssertEqual(prefix, String(rawInvoice.prefix(14)))
        XCTAssertEqual(middle, "········")
        XCTAssertEqual(suffix, String(rawInvoice.suffix(10)))
        XCTAssertTrue(rawInvoice.hasSuffix(suffix))
    }
}
