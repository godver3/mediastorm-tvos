import SwiftUI

/// How large titles' logos are drawn, against their usual size.
enum LogoScale: Int, CaseIterable, Identifiable, Sendable {
    case p25 = 25, p50 = 50, p75 = 75, p100 = 100, p125 = 125

    var id: Int { rawValue }
    var label: String { "\(rawValue)%" }
    var factor: CGFloat { CGFloat(rawValue) / 100 }
}

/// Settings › Home › Title Logo Size: scales the title logos on Home (Focused Title Info
/// and Top Carousel) and on details pages. Device only; 100% by default.
@MainActor
final class LogoSettingsStore: ObservableObject {
    static let shared = LogoSettingsStore()

    @Published var scale: LogoScale {
        didSet { defaults.set(scale.rawValue, forKey: Self.key) }
    }

    private let defaults = UserDefaults.standard
    private static let key = "strmrtv.logoScale"

    private init() {
        _scale = Published(initialValue: LogoScale(rawValue: defaults.integer(forKey: Self.key)) ?? .p100)
    }
}
