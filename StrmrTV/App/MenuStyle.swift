import SwiftUI

/// Where the main menu sits: the top tab bar (the default) or the system sidebar on the
/// left. The profile has no matching server field (the Expo TV app always
/// uses its drawer), so Default is the top bar.
enum MenuStyle: String, CaseIterable, Identifiable, Sendable {
    case top, side

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .top: "Top Bar"
        case .side: "Side Menu"
        }
    }
}

/// This device's menu style, saved locally.
@MainActor
final class MenuStyleStore: ObservableObject {
    static let shared = MenuStyleStore()
    private static let log = AppLog(category: "menustyle")

    private let defaults: UserDefaults
    private static let key = "menu.style"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _choice = Published(initialValue: defaults.string(forKey: Self.key).flatMap(MenuStyle.init(rawValue:)))
        Self.log.info("menu style \(style.rawValue)")
    }

    /// This device's choice; nil (Default) is the top bar.
    @Published var choice: MenuStyle? {
        didSet {
            guard choice != oldValue else { return }
            defaults.set(choice?.rawValue, forKey: Self.key)
            Self.log.info("menu style \(style.rawValue)")
        }
    }

    var style: MenuStyle { choice ?? .top }
}

/// The tab view in the chosen style: as it always was (the top bar), or `.sidebarAdaptable`,
/// the system sidebar on tvOS: the same tabs, collapsed to a glass pill naming the current
/// one at the top left, and opened over the content (icons and labels) when focus moves
/// Left into it or Menu is pressed on a tab's root. Select or Right goes back to the
/// content. The two branches are different views, so switching rebuilds the tabs' views;
/// the selected tab and Home's pushed pages live on `MainTabs` and are kept.
struct MenuStyleModifier: ViewModifier {
    let style: MenuStyle

    func body(content: Content) -> some View {
        switch style {
        case .top: content
        case .side: content.tabViewStyle(.sidebarAdaptable).environment(\.sidebarInset, Self.pillClearance)
        }
    }

    /// How far a page's top must come down to clear the collapsed sidebar pill. The pill
    /// floats at the top left of every page, pushed ones included (y 51-110 on the 1080
    /// screen), where the top bar would have hidden itself or pushed the content down; a
    /// page's first row sits at the 60 pt safe area, so this brings it 20 pt below the pill.
    static let pillClearance: CGFloat = 70
}

extension EnvironmentValues {
    /// The room a page leaves at its top for the side menu's collapsed pill: zero with the
    /// top bar, so those pages are unchanged. Pages whose title row reaches the pill's
    /// corner (pushed grids, Search) pad their title row by it; the others sit clear of it.
    @Entry var sidebarInset: CGFloat = 0
}

