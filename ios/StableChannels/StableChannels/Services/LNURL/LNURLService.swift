import Foundation

// MARK: - Models

/// LNURL-pay parameters returned from LUD-06 first-step GET request.
struct LNURLPayParams: Codable, Equatable, Sendable {
    let tag: String
    let callback: String
    let minSendable: UInt64 // millisatoshis
    let maxSendable: UInt64 // millisatoshis
    let metadata: String
    let commentAllowed: Int?

    var minSats: UInt64 {
        (minSendable + 999) / 1000
    }

    var maxSats: UInt64 {
        maxSendable / 1000
    }

    var hasCustomSendBounds: Bool {
        minSats > 1 || maxSats < 2_100_000_000_000_000
    }

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
struct LNURLSuccessAction: Codable, Equatable, Sendable {
    let tag: String
    let description: String?
    let url: String?
    let message: String?
}

/// Invoice response returned from LNURL-pay second-step GET request.
struct LNURLPayInvoiceResponse: Codable, Equatable, Sendable {
    let pr: String
    let successAction: LNURLSuccessAction?
    let status: String?
    let reason: String?
}

// MARK: - Protocol

protocol LNURLServiceProtocol: Sendable {
    func fetchPayParams(from url: URL) async throws -> LNURLPayParams
    func fetchInvoice(callback: String, amountMsat: UInt64, comment: String?) async throws -> LNURLPayInvoiceResponse
}

// MARK: - Errors

enum LNURLError: Swift.Error, LocalizedError {
    case invalidTarget
    case invalidResponse
    case errorResponse(reason: String)
    case unsupportedTag(tag: String)
    case amountOutOfBounds(minSats: UInt64, maxSats: UInt64)
    case invoiceAmountMismatch(expectedMsat: UInt64, actualMsat: UInt64)
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
        case let .invoiceAmountMismatch(expected, actual):
            return "Invoice amount (\(actual / 1000) sats) does not match requested amount (\(expected / 1000) sats)."
        case let .networkError(msg):
            return "LNURL network request failed: \(msg)"
        }
    }
}

// MARK: - Service Implementation

final class LNURLService: LNURLServiceProtocol {
    private let urlSession: URLSession

    init(urlSession: URLSession? = nil) {
        if let session = urlSession {
            self.urlSession = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15.0
            config.timeoutIntervalForResource = 30.0
            self.urlSession = URLSession(configuration: config)
        }
    }

    func fetchPayParams(from url: URL) async throws -> LNURLPayParams {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw LNURLError.networkError(error.localizedDescription)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let reason = json["reason"] as? String, !reason.isEmpty {
                throw LNURLError.errorResponse(reason: reason)
            }
            if let status = json["status"] as? String, status.uppercased() == "ERROR" {
                let reason = (json["reason"] as? String) ?? "The recipient service reported an error."
                throw LNURLError.errorResponse(reason: reason)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                throw LNURLError.errorResponse(reason: "Recipient address not found.")
            }
            throw LNURLError.invalidResponse
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

    func fetchInvoice(callback: String, amountMsat: UInt64, comment: String?) async throws -> LNURLPayInvoiceResponse {
        guard let initialUrl = URL(string: callback),
              let scheme = initialUrl.scheme?.lowercased() else {
            throw LNURLError.invalidResponse
        }

        let isHttps = scheme == "https"
        let isOnionHttp = scheme == "http" && (initialUrl.host?.lowercased().hasSuffix(".onion") == true)
        guard isHttps || isOnionHttp else {
            throw LNURLError.networkError("LNURL callback requires HTTPS for clearnet endpoints.")
        }

        guard var components = URLComponents(url: initialUrl, resolvingAgainstBaseURL: false) else {
            throw LNURLError.invalidResponse
        }

        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "amount", value: "\(amountMsat)"))
        if let comment, !comment.isEmpty {
            queryItems.append(URLQueryItem(name: "comment", value: comment))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw LNURLError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw LNURLError.networkError(error.localizedDescription)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let reason = json["reason"] as? String, !reason.isEmpty {
                throw LNURLError.errorResponse(reason: reason)
            }
            if let status = json["status"] as? String, status.uppercased() == "ERROR" {
                let reason = (json["reason"] as? String) ?? "The recipient service reported an error."
                throw LNURLError.errorResponse(reason: reason)
            }
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw LNURLError.invalidResponse
        }

        let decoder = JSONDecoder()
        guard let invoiceResponse = try? decoder.decode(LNURLPayInvoiceResponse.self, from: data) else {
            throw LNURLError.invalidResponse
        }

        return invoiceResponse
    }
}
