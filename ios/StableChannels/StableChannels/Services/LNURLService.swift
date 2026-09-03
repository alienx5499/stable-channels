import Foundation

// MARK: - Models

/// Represents a parsed LNURL or Lightning Address destination.
enum LNURLTarget: Equatable, Hashable {
    case lightningAddress(handle: String, domain: String, url: URL)
    case lnurlPay(url: URL)

    var url: URL {
        switch self {
        case let .lightningAddress(_, _, url):
            return url
        case let .lnurlPay(url):
            return url
        }
    }

    var displayDestination: String {
        switch self {
        case let .lightningAddress(handle, domain, _):
            return "\(handle)@\(domain)"
        case let .lnurlPay(url):
            return url.host ?? url.absoluteString
        }
    }
}

/// LNURL-pay parameters returned from LUD-06 first-step GET request.
struct LNURLPayParams: Codable, Equatable {
    let tag: String
    let callback: String
    let minSendable: UInt64 // millisatoshis
    let maxSendable: UInt64 // millisatoshis
    let metadata: String
    let commentAllowed: Int?
    let nostrPubkey: String?
    let allowsNostr: Bool?

    var minSats: UInt64 {
        (minSendable + 999) / 1000
    }

    var maxSats: UInt64 {
        maxSendable / 1000
    }

    /// True if the recipient has custom non-default bounds (not just the typical 1 sat to ~1 BTC range).
    var hasCustomSendBounds: Bool {
        minSats > 1 || maxSats < 21_000_000
    }

    /// Extracts the "text/plain" description from the LUD-06 metadata JSON string.
    var plainTextDescription: String? {
        guard let data = metadata.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String]] else {
            return nil
        }
        for item in jsonArray where item.count >= 2 && item[0] == "text/plain" {
            return item[1]
        }
        return nil
    }
}

/// Success action returned after LNURL payment request (LUD-09 / LUD-10).
struct LNURLSuccessAction: Codable, Equatable {
    let tag: String
    let description: String?
    let url: String?
    let message: String?
}

/// Invoice response returned from LNURL-pay second-step GET request.
struct LNURLPayInvoiceResponse: Codable, Equatable {
    let pr: String
    let successAction: LNURLSuccessAction?
    let status: String?
    let reason: String?
}

// MARK: - Protocol

protocol LNURLServiceProtocol: Sendable {
    func parseInput(_ raw: String) -> LNURLTarget?
    func fetchPayParams(from target: LNURLTarget) async throws -> LNURLPayParams
    func fetchInvoice(callback: String, amountMsat: UInt64, comment: String?) async throws -> LNURLPayInvoiceResponse
}

// MARK: - Service Implementation

final class LNURLService: LNURLServiceProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    enum LNURLError: Swift.Error, LocalizedError {
        case invalidTarget
        case invalidResponse
        case errorResponse(reason: String)
        case unsupportedTag(tag: String)
        case amountOutOfBounds(minSats: UInt64, maxSats: UInt64)
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .invalidTarget:
                return "The provided address or LNURL is invalid."
            case .invalidResponse:
                return "Received an invalid or malformed response from the LNURL server."
            case let .errorResponse(reason):
                return reason
            case let .unsupportedTag(tag):
                return "Unsupported LNURL tag: \(tag). Only LNURL-pay is supported."
            case let .amountOutOfBounds(minSats, maxSats):
                return "Amount must be between \(minSats) and \(maxSats) sats."
            case let .networkError(msg):
                return "LNURL network request failed: \(msg)"
            }
        }
    }

    // MARK: - Input Parsing (LUD-01, LUD-06, LUD-16)

    func parseInput(_ raw: String) -> LNURLTarget? {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("lightning:") {
            clean = String(clean.dropFirst("lightning:".count))
        }

        // 1. Fast Lightning Address parsing: user@domain.com (LUD-16)
        if let atIndex = clean.firstIndex(of: "@") {
            let handle = clean[..<atIndex]
            let domain = clean[clean.index(after: atIndex)...]
            if !handle.isEmpty, !domain.isEmpty, domain.contains(".") {
                let domainStr = String(domain)
                let handleStr = String(handle)
                let isLocalOrOnion = domainStr.hasSuffix(".onion") || domainStr.hasPrefix("localhost") || domainStr
                    .hasPrefix("127.0.0.1")
                let scheme = isLocalOrOnion ? "http" : "https"
                if let url = URL(string: "\(scheme)://\(domainStr)/.well-known/lnurlp/\(handleStr)") {
                    return .lightningAddress(handle: handleStr, domain: domainStr, url: url)
                }
            }
        }

        // 2. Check for Bech32 LNURL: lnurl1... (LUD-01)
        if clean.lowercased().hasPrefix("lnurl1") {
            if let decodedURL = try? Bech32.decodeLNURL(clean) {
                return .lnurlPay(url: decodedURL)
            }
        }

        // 3. Check for direct HTTPS / HTTP LNURL URL with lnurlp query parameter
        if let directURL = URL(string: clean),
           directURL.scheme == "https" || directURL.scheme == "http",
           directURL.path.contains("lnurl") || (directURL.query?.contains("lnurl") == true) {
            return .lnurlPay(url: directURL)
        }

        return nil
    }

    // MARK: - Fetch Pay Request Parameters (LUD-06 Step 1)

    func fetchPayParams(from target: LNURLTarget) async throws -> LNURLPayParams {
        var request = URLRequest(url: target.url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LNURLError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LNURLError.invalidResponse
        }

        // Check if server returned an error JSON
        if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = errorObj["status"] as? String,
           status.uppercased() == "ERROR",
           let reason = errorObj["reason"] as? String {
            throw LNURLError.errorResponse(reason: reason)
        }

        let decoder = JSONDecoder()
        guard let params = try? decoder.decode(LNURLPayParams.self, from: data) else {
            throw LNURLError.invalidResponse
        }

        guard params.tag.lowercased() == "payrequest" else {
            throw LNURLError.unsupportedTag(tag: params.tag)
        }

        return params
    }

    // MARK: - Fetch BOLT11 Invoice (LUD-06 Step 2)

    func fetchInvoice(
        callback: String,
        amountMsat: UInt64,
        comment: String? = nil
    ) async throws -> LNURLPayInvoiceResponse {
        guard var components = URLComponents(string: callback) else {
            throw LNURLError.invalidTarget
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "amount", value: String(amountMsat)))

        if let comment = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            queryItems.append(URLQueryItem(name: "comment", value: comment))
        }

        components.queryItems = queryItems
        guard let finalURL = components.url else {
            throw LNURLError.invalidTarget
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LNURLError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LNURLError.invalidResponse
        }

        // Check for error JSON
        if let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = errorObj["status"] as? String,
           status.uppercased() == "ERROR",
           let reason = errorObj["reason"] as? String {
            throw LNURLError.errorResponse(reason: reason)
        }

        let decoder = JSONDecoder()
        guard let invoiceResponse = try? decoder.decode(LNURLPayInvoiceResponse.self, from: data) else {
            throw LNURLError.invalidResponse
        }

        if let status = invoiceResponse.status, status.uppercased() == "ERROR" {
            throw LNURLError.errorResponse(reason: invoiceResponse.reason ?? "Unknown error from LNURL provider.")
        }

        return invoiceResponse
    }
}
