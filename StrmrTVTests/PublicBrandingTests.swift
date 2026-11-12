import XCTest
@testable import StrmrTV

/// Admin-uploaded branding paths resolve under the server's `/api` prefix.
final class PublicBrandingTests: XCTestCase {
    private let server = URL(string: "http://192.168.1.10:7777")!

    func testUploadedPathResolvesUnderAPI() {
        let url = PublicBranding.resolve("/branding/images/loading-logo?v=12", server: server)
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.10:7777/api/branding/images/loading-logo?v=12")
    }

    func testKeepsServerSubPathAndExistingAPIPrefix() {
        let proxied = URL(string: "https://host.example/mediastorm/")!
        XCTAssertEqual(
            PublicBranding.resolve("/branding/images/home-tv", server: proxied)?.absoluteString,
            "https://host.example/mediastorm/api/branding/images/home-tv")
        XCTAssertEqual(
            PublicBranding.resolve("/api/branding/images/home-tv", server: server)?.absoluteString,
            "http://192.168.1.10:7777/api/branding/images/home-tv")
    }

    func testAbsoluteURLAndBlankPaths() {
        XCTAssertEqual(
            PublicBranding.resolve("https://cdn.example/logo.png", server: server)?.absoluteString,
            "https://cdn.example/logo.png")
        XCTAssertNil(PublicBranding.resolve("  ", server: server))
        XCTAssertNil(PublicBranding.resolve(nil, server: server))
    }

    func testProfilePickerPrefersTVImageOnTVAndMobileLogoOnPhone() {
        let both = PublicBranding(loadingLogoUrl: "/l", homeMobileLogoUrl: "/m", homeTvImageUrl: "/t")
        XCTAssertEqual(both.profilePickerPath(tv: true), "/t")
        XCTAssertEqual(both.profilePickerPath(tv: false), "/m")
        XCTAssertEqual(both.logoPath, "/l")

        let mobileOnly = PublicBranding(loadingLogoUrl: nil, homeMobileLogoUrl: "/m", homeTvImageUrl: " ")
        XCTAssertEqual(mobileOnly.profilePickerPath(tv: true), "/m")
        let tvOnly = PublicBranding(loadingLogoUrl: nil, homeMobileLogoUrl: nil, homeTvImageUrl: "/t")
        XCTAssertEqual(tvOnly.profilePickerPath(tv: false), "/t")
    }
}
