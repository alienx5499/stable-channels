@testable import StableChannels
import XCTest

final class UpdateAvailableTests: XCTestCase {
    private func v(_ string: String) -> AppVersion {
        AppVersion(string)!
    }

    // MARK: - AppVersion and UpdatePolicy

    func testComparesNumerically() {
        XCTAssertGreaterThan(v("0.9.10"), v("0.9.2"))
        XCTAssertLessThan(v("0.9.2"), v("1.0"))
    }

    func testMissingComponentsAreZero() {
        XCTAssertEqual(v("1.0"), v("1.0.0"))
        XCTAssertFalse(v("1.0") < v("1.0.0"))
    }

    func testRejectsNonNumeric() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.x"))
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1..2"))
    }

    func testShowsWhenStoreIsNewer() {
        XCTAssertTrue(UpdatePolicy.shouldShow(installed: v("0.9.2"), store: v("0.9.3"), dismissed: nil))
    }

    func testNoUpdateWhenInstalledIsNewer() {
        XCTAssertFalse(UpdatePolicy.shouldShow(installed: v("0.9.4"), store: v("0.9.3"), dismissed: nil))
        XCTAssertFalse(UpdatePolicy.shouldShow(installed: v("0.9.3"), store: v("0.9.3"), dismissed: nil))
    }

    func testDismissedVersionHides() {
        XCTAssertFalse(UpdatePolicy.shouldShow(installed: v("0.9.2"), store: v("0.9.3"), dismissed: v("0.9.3")))
    }

    func testNewerThanDismissedShows() {
        XCTAssertTrue(UpdatePolicy.shouldShow(installed: v("0.9.2"), store: v("0.9.4"), dismissed: v("0.9.3")))
    }

    func testUnknownVersionsHide() {
        XCTAssertFalse(UpdatePolicy.shouldShow(installed: nil, store: v("0.9.3"), dismissed: nil))
        XCTAssertFalse(UpdatePolicy.shouldShow(installed: v("0.9.2"), store: nil, dismissed: nil))
    }

    // MARK: - AppStoreUpdateService

    private func service(returning body: String) -> AppStoreUpdateService {
        AppStoreUpdateService(fetch: { _ in Data(body.utf8) })
    }

    func testDecodesLatestRelease() async throws {
        let release = await service(returning: """
        {"resultCount":1,"results":[{"version":"0.9.3","trackViewUrl":"https://apps.apple.com/app/id1"}]}
        """).latestRelease(bundleId: "com.stablechannels.app", country: "us")

        XCTAssertEqual(
            release,
            StoreRelease(version: v("0.9.3"), url: try XCTUnwrap(URL(string: "https://apps.apple.com/app/id1")))
        )
    }

    func testRequestsBundleAndCountry() async {
        let requested = RequestedURL()
        let service = AppStoreUpdateService(fetch: { url in
            await requested.set(url)
            return Data(#"{"resultCount":0,"results":[]}"#.utf8)
        })

        _ = await service.latestRelease(bundleId: "com.stablechannels.app", country: "de")

        let query = await requested.url?.query ?? ""
        XCTAssertTrue(query.contains("bundleId=com.stablechannels.app"), query)
        XCTAssertTrue(query.contains("country=de"), query)
    }

    func testNoResultsIsNil() async {
        let release = await service(returning: #"{"resultCount":0,"results":[]}"#)
            .latestRelease(bundleId: "com.stablechannels.app", country: "us")
        XCTAssertNil(release)
    }

    func testMalformedIsNil() async {
        let release = await service(returning: "not json").latestRelease(
            bundleId: "com.stablechannels.app",
            country: "us"
        )
        XCTAssertNil(release)
    }

    func testNetworkErrorIsNil() async {
        let service = AppStoreUpdateService(fetch: { _ in throw URLError(.notConnectedToInternet) })
        let release = await service.latestRelease(bundleId: "com.stablechannels.app", country: "us")
        XCTAssertNil(release)
    }
}

private actor RequestedURL {
    private(set) var url: URL?

    func set(_ url: URL) {
        self.url = url
    }
}
