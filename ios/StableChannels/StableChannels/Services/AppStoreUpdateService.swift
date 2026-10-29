import Foundation

/// The app's latest release on the App Store.
struct StoreRelease: Equatable {
    let version: AppVersion
    let url: URL
}

/// Reads the latest release from Apple's public lookup API. Any failure (offline, not on the store
/// yet, unexpected reply) returns nil, so the app simply shows no update.
struct AppStoreUpdateService {
    private let fetch: (URL) async throws -> Data

    init(fetch: @escaping (URL) async throws -> Data = { try await URLSession.shared.data(from: $0).0 }) {
        self.fetch = fetch
    }

    func latestRelease(bundleId: String, country: String) async -> StoreRelease? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "country", value: country)
        ]
        guard let url = components?.url else { return nil }
        do {
            let data = try await fetch(url)
            let response = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let result = response.results.first,
                  let version = AppVersion(result.version),
                  let storeURL = URL(string: result.trackViewUrl) else { return nil }
            return StoreRelease(version: version, url: storeURL)
        } catch {
            AuditService.log("APP_UPDATE_CHECK_FAILED", data: ["error": "\(error)"])
            return nil
        }
    }

    private struct LookupResponse: Decodable {
        struct Result: Decodable {
            let version: String
            let trackViewUrl: String
        }

        let results: [Result]
    }
}
