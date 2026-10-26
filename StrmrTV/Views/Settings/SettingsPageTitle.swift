import SwiftUI

/// A settings page's title as the first row of its list, so it scrolls away with the
/// rows. tvOS pins `navigationTitle` above the content, and long pages then scroll
/// underneath it. Pair with `.settingsSubpage()` on the page.
struct SettingsPageTitle: View {
    let title: Text

    init(_ title: LocalizedStringKey) { self.title = Text(title) }
    init(_ title: Text) { self.title = title }

    var body: some View {
        Section {
            title
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

extension View {
    /// A page pushed from Settings: no pinned navigation title (the page draws
    /// `SettingsPageTitle`), and no tab bar, as on Details. tvOS hides the tab bar while
    /// a pushed list scrolls and doesn't bring it back on pop, so the subpage takes it
    /// down itself and the system restores it when Settings shows again.
    func settingsSubpage() -> some View {
        toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }

    /// Room inside a settings list for the focused row's lift, so it isn't clipped at
    /// the sides. `Form` ignores `contentMargins` (vertically it only honours them once
    /// focus scrolls, so a fresh page sat 40 pt high and jumped down on the first
    /// focus); safe-area padding insets its rows from the start.
    func settingsListMargins(_ horizontal: CGFloat = 50) -> some View {
        safeAreaPadding(.horizontal, horizontal)
            .safeAreaPadding(.vertical, 40)
    }
}
