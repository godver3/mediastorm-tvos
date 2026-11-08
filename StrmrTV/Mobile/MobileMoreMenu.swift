#if os(iOS)
import SwiftUI
import UIKit

/// The signed-in app's shared stores, created once. Never publishes itself, so the tab
/// view holding it doesn't re-render when one of them changes.
@MainActor
final class MobileMainStores: ObservableObject {
    let watchlist = WatchlistStore()
    let customLists = CustomListsStore()
    let titles = TitleStateStore()
    let listShelves = ListShelvesStore()
}

/// A tab of the phone's tab view: a section, or More (the sections past the tab bar).
enum MobileTab: Hashable {
    case section(MobileSection)
    case more
}

/// Which sections are tabs and which sit behind More. A compact-width tab bar holds five
/// items whatever the phone's width: past that UIKit moves the rest into its own More,
/// which stacks a second navigation bar on each page under it. So with more than five
/// sections the bar keeps Search (the bar's search tab) and More, and fills the other
/// slots with the first sections in order.
struct MobileTabSplit: Equatable {
    /// Items a compact tab bar shows before UIKit adds its own More.
    static let compactSlots = 5

    let tabs: [MobileSection]
    let more: [MobileSection]

    init(sections: [MobileSection], compact: Bool) {
        guard compact, sections.count > Self.compactSlots else {
            tabs = sections
            more = []
            return
        }
        let regular = sections.filter { $0 != .search }
        let shown = Set(regular.prefix(Self.compactSlots - 1 - (sections.contains(.search) ? 1 : 0)))
        tabs = sections.filter { $0 == .search || shown.contains($0) }
        more = regular.filter { !shown.contains($0) }
    }
}

extension View {
    /// The More tab's menu: a popover over the tab bar's More button listing `sections`,
    /// the one shown (`current`) checked.
    func mobileMoreMenu(isPresented: Binding<Bool>, sections: [MobileSection], current: MobileSection?,
                        onChoose: @escaping (MobileSection) -> Void) -> some View {
        modifier(MobileMoreMenu(isPresented: isPresented, sections: sections, current: current, onChoose: onChoose))
    }
}

/// Presents the menu as a native popover pointing at the More button. SwiftUI has no way
/// to hang a menu off a tab item, so the popover is anchored at the button's frame, read
/// from the tab bar's accessibility elements when it opens (the middle of the bar if that
/// fails).
struct MobileMoreMenu: ViewModifier {
    static let title = String(localized: "More")

    @Binding var isPresented: Bool
    let sections: [MobileSection]
    let current: MobileSection?
    let onChoose: (MobileSection) -> Void

    @State private var anchor: CGRect?
    @State private var shows = false

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    let rect = (anchor ?? .zero).offsetBy(dx: -origin.x, dy: -origin.y)
                    Color.clear
                        .allowsHitTesting(false)
                        .popover(isPresented: $shows, attachmentAnchor: .rect(.rect(rect)), arrowEdge: .bottom) {
                            menu.presentationCompactAdaptation(.popover)
                        }
                }
                .ignoresSafeArea()
            }
            .onChange(of: isPresented) { _, presented in
                if presented { anchor = MobileTabBarLocator.frame(ofItem: Self.title) }
                shows = presented
            }
            .onChange(of: shows) { _, shown in if !shown { isPresented = false } }
    }

    private var menu: some View {
        VStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element) { index, section in
                if index > 0 { Divider() }
                Button {
                    shows = false
                    onChoose(section)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: section.symbol)
                            .frame(width: 24)
                            .foregroundStyle(section == current ? Color.accentColor : .secondary)
                        Text(section.title)
                        Spacer(minLength: 16)
                        if section == current {
                            Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == current ? .isSelected : [])
            }
        }
        .frame(minWidth: 220)
        .padding(.vertical, 4)
    }
}

/// Finds a tab bar item's frame, in window coordinates, by its accessibility label.
@MainActor
enum MobileTabBarLocator {
    static func frame(ofItem label: String) -> CGRect? {
        guard let window = keyWindow else { return nil }
        let bars = descendants(of: window).compactMap { $0 as? UITabBar }
        guard let bar = bars.first(where: { !$0.isHidden && $0.window != nil }) else { return nil }
        for view in descendants(of: bar) {
            if let frame = match(view, label: label, in: window) { return frame }
        }
        // Not found: the top middle of the bar, where the popover still reads as its menu.
        let frame = bar.convert(bar.bounds, to: window)
        return CGRect(x: frame.midX - 1, y: frame.minY, width: 2, height: 2)
    }

    private static func match(_ view: UIView, label: String, in window: UIWindow) -> CGRect? {
        if view.accessibilityLabel == label, !view.isHidden {
            return view.convert(view.bounds, to: window)
        }
        for case let element as NSObject in view.accessibilityElements ?? [] where element.accessibilityLabel == label {
            return window.convert(element.accessibilityFrame, from: window.screen.coordinateSpace)
        }
        return nil
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
#endif
