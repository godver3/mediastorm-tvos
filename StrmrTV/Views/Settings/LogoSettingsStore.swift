import SwiftUI

/// How large titles' logos are drawn, against their usual size.
enum LogoScale: Int, CaseIterable, Identifiable, Sendable {
    case p25 = 25, p50 = 50, p75 = 75, p100 = 100, p125 = 125, p150 = 150

    var id: Int { rawValue }
    var label: String { "\(rawValue)%" }
    var factor: CGFloat { CGFloat(rawValue) / 100 }
}

/// Where a title logo is drawn, each with its own Title Logo Size.
enum LogoPlace: Sendable {
    /// Focused Title Info and the Top Carousel.
    case home
    /// The details page header.
    case details
}

/// Settings › Home › Title Logo Size: scales the title logos on Home (Focused Title Info
/// and Top Carousel) and, separately, on details pages. Device only; 100% by default.
@MainActor
final class LogoSettingsStore: ObservableObject {
    static let shared = LogoSettingsStore()

    @Published var scale: LogoScale {
        didSet { defaults.set(scale.rawValue, forKey: Self.key) }
    }

    @Published var detailsScale: LogoScale {
        didSet { defaults.set(detailsScale.rawValue, forKey: Self.detailsKey) }
    }

    func scale(for place: LogoPlace) -> LogoScale {
        switch place {
        case .home: scale
        case .details: detailsScale
        }
    }

    private let defaults = UserDefaults.standard
    /// The Home size; before details had its own, it sized both.
    private static let key = "strmrtv.logoScale"
    private static let detailsKey = "strmrtv.detailsLogoScale"

    private init() {
        let home = LogoScale(rawValue: defaults.integer(forKey: Self.key)) ?? .p100
        _scale = Published(initialValue: home)
        // Unset: keeps the size the shared setting gave details pages.
        _detailsScale = Published(initialValue: LogoScale(rawValue: defaults.integer(forKey: Self.detailsKey)) ?? home)
    }
}
