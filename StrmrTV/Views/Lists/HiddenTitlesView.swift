import SwiftUI

/// Titles hidden from the profile, as posters; long press offers Unhide (the title then
/// rejoins Home and the lists). The Expo app has no such page; hidden titles there come
/// back only from the server's admin pages.
struct HiddenTitlesView: View {
    @EnvironmentObject private var titles: TitleStateStore
    @State private var gridWidth: CGFloat = 0

    var body: some View {
        GridPage(title: String(localized: "Hidden"), gridWidth: $gridWidth) {
            if titles.hidden.isEmpty {
                GridMessage(text: titles.hiddenLoaded
                    ? String(localized: "Nothing is hidden from this profile.")
                    : String(localized: "Loading…"),
                    holdsFocus: titles.hiddenLoaded)
            } else {
                Text("Long press a title to unhide it.")
                    .font(.callout).foregroundStyle(.secondary)
                CardGrid(items: titles.hidden, cardWidth: PosterCard.width, available: gridWidth) { item, width in
                    PosterCard(hidden: item, width: width)
                }
            }
        }
        .task { await titles.refreshHidden() }
    }
}
