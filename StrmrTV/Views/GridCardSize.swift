import SwiftUI

/// How big the cards are on list grids (lists, streaming services, Watchlist, Continue
/// Watching, Hidden, a person's titles). One size for every grid, so changing it on one
/// list changes them all.
enum GridCardSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        case .extraLarge: String(localized: "Extra Large")
        }
    }

    /// The factor on a card's base width; the grid fits as many columns as that allows.
    var scale: CGFloat {
        switch self {
        case .small: 0.75
        case .medium: 1
        case .large: 1.3
        case .extraLarge: 1.7
        }
    }
}

/// This device's grid card size, saved locally.
@MainActor
final class GridCardSizeStore: ObservableObject {
    static let shared = GridCardSizeStore()
    private static let log = AppLog(category: "gridsize")

    private let defaults: UserDefaults
    private static let key = "grid.cardSize"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _size = Published(initialValue: defaults.string(forKey: Self.key).flatMap(GridCardSize.init(rawValue:)) ?? .medium)
    }

    @Published var size: GridCardSize {
        didSet {
            guard size != oldValue else { return }
            defaults.set(size.rawValue, forKey: Self.key)
            Self.log.info("grid card size \(size.rawValue)")
        }
    }
}

/// The grid card size menu, beside a grid page's heading or the Watchlist's filter.
struct GridCardSizeMenu: View {
    @ObservedObject private var store = GridCardSizeStore.shared

    var body: some View {
        Menu {
            Picker("Card Size", selection: $store.size) {
                ForEach(GridCardSize.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label(String(localized: "Card Size: \(store.size.label)"), systemImage: "square.grid.2x2")
        }
        .font(.callout)
        .accessibilityLabel("Card Size")
    }
}
