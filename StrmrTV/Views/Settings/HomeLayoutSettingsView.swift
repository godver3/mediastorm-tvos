import SwiftUI

/// Settings › Home Layout: how Home lays out its rows on this device. Each choice
/// starts on the server's value ("Default") and is saved on this device only.
struct HomeLayoutSettingsView: View {
    @ObservedObject private var layout = HomeLayoutStore.shared
    @ObservedObject private var style = HomeStyleStore.shared

    var body: some View {
        Form {
            SettingsPageTitle("Home Layout")
            styleSection
            Section {
                // Hero Size sizes Focused Title Info; the carousel has its own size.
                if style.focusedInfo {
                    OverridePicker("Hero Size", selection: $layout.heroSize, options: HeroSize.allCases,
                                   profileValue: layout.profile.heroSize) { $0.label }
                }
                if style.focusedInfo || style.topCarousel {
                    ChoiceRow(title: textSizeTitle, selection: $layout.heroTextSize,
                              choices: HeroTextSize.allCases.map { .init(value: $0, text: Text($0.label)) })
                }
                OverridePicker("Card Size", selection: $layout.cardSize, options: CardSize.allCases,
                               profileValue: CardSize(nearest: layout.profile.cardScale)) { $0.label }
                ForEach(ShelfStyle.allCases) { rowStyle in
                    OverridePicker(rowStyle.cardSizeTitle, selection: styleCardSize(rowStyle), options: CardSize.allCases,
                                   profileValue: CardSize(nearest: layout.effectiveCardScale)) { $0.label }
                }
                OverridePicker("Card Titles", selection: $layout.cardText, options: CardText.allCases,
                               profileValue: HomeLayoutStore.defaultCardText) { $0.label }
            } header: {
                Text("Size")
            } footer: {
                Text(sizeFooter)
            }

            Section {
                Toggle("View Switcher on Home", isOn: $layout.viewSwitcher)
            } header: {
                Text("Views")
            } footer: {
                Text("A button on Home that switches it between All, Movies, Shows and your pages. Not shown while every view has its own tab in Settings › Menu.")
            }

            Section {
                OverridePicker("Focused Card Position", selection: $layout.focusPosition,
                               options: FocusedCardPosition.allCases,
                               profileValue: layout.profile.focusPosition) { $0.label }
            } header: {
                Text("Focus")
            } footer: {
                Text("Where the focused card sits in a row as you move along it.")
            }

            Section {
                OverridePicker("Expand Posters on Focus", selection: $layout.expandPosters, options: [true, false],
                               profileValue: layout.profile.expandPosters) { $0 ? "On" : "Off" }
                if layout.usesExpandingPosters {
                    Toggle("Animate Expansion", isOn: $layout.animateExpansion)
                }
            } header: {
                Text("Cards")
            } footer: {
                Text("In poster rows, the focused poster opens to a wide card. Applies to rows set to Default. Animate Expansion opens and folds the card in motion; off, it snaps open.")
            }

            Section {
                if layout.shelves.isEmpty {
                    Text("Open Home to list its rows.").foregroundStyle(.secondary)
                }
                ForEach(layout.shelves) { shelf in
                    ShelfStylePicker(shelf: shelf)
                }
                if !layout.shelfStyles.isEmpty || !layout.hiddenShelves.isEmpty {
                    Button("Reset All Rows to Default") { layout.resetShelfStyles() }
                }
            } header: {
                Text("Rows")
            } footer: {
                Text("Hidden rows are left off Home on this device. As in the Expo app, Continue Watching, My Upcoming, Watch Something, Dashboard, Streaming Services, Recently Watched and collection rows default to wide cards; other rows to posters.")
            }
        }
        .settingsSubpage()
        .settingsListMargins(80)
    }

    /// One kind of row's card size; Default follows Card Size.
    private func styleCardSize(_ style: ShelfStyle) -> Binding<CardSize?> {
        Binding { layout.styleCardSizes[style] } set: { layout.styleCardSizes[style] = $0 }
    }

    /// The Hero Text Size choice also sizes the carousel's text; named for what it sizes.
    private var textSizeTitle: LocalizedStringKey {
        style.focusedInfo ? "Hero Text Size" : "Carousel Text Size"
    }

    private var sizeFooter: LocalizedStringKey {
        switch (style.topCarousel, style.focusedInfo) {
        case (true, true):
            "A smaller hero, smaller cards and card titles overlaid on the art (or none) fit more rows on screen. Poster, Expanding Poster and Landscape Cards size those rows alone; Default follows Card Size. Hero Text Size also sizes the carousel's text."
        case (false, true):
            "A smaller hero, smaller cards and card titles overlaid on the art (or none) fit more rows on screen. Poster, Expanding Poster and Landscape Cards size those rows alone; Default follows Card Size. Hero Size Off keeps the backdrop but hides the title and overview."
        default:
            "Smaller cards and card titles overlaid on the art (or none) fit more rows on screen. Poster, Expanding Poster and Landscape Cards size those rows alone; Default follows Card Size."
        }
    }

    /// Top Carousel (and the row it shows) and Focused Title Info.
    private var styleSection: some View {
        Section {
            Toggle("Top Carousel", isOn: $style.topCarousel)
            if style.topCarousel {
                if layout.shelves.isEmpty {
                    Text("Open Home to list its rows.").foregroundStyle(.secondary)
                } else {
                    ChoiceRow(title: "Carousel Row", selection: $style.carouselRow,
                              defaultValue: HomeStyleStore.defaultRow(in: layout.shelves.map(\.id)),
                              choices: layout.shelves.map { .init(value: $0.id, name: $0.title) })
                }
            }
            Toggle("Focused Title Info", isOn: $style.focusedInfo)
            // The full hero shows one shelf to a screen; smaller ones scroll a list of rows.
            if style.focusedInfo && layout.effectiveHeroSize == .full {
                ChoiceRow(title: "Shelf Transition", selection: $style.shelfTransition,
                          choices: ShelfTransition.allCases.map { .init(value: $0, text: Text($0.label)) })
            }
        } header: {
            Text("Top of Home")
        } footer: {
            Text("Top Carousel: a large carousel of one row's titles above the rows; that row isn't repeated below. Focused Title Info: the focused card's title, overview and backdrop above the rows. Off, the rows move up into its space. Shelf Transition (Full hero): Slide scrolls to the next shelf; Swap fades one shelf out and the next in.")
        }
    }
}

/// A picker whose first option follows the server ("Default (Left)"); the
/// others set this device's own value.
struct OverridePicker<Value: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var selection: Value?
    let options: [Value]
    let profileValue: Value
    let label: (Value) -> LocalizedStringKey

    init(_ title: LocalizedStringKey, selection: Binding<Value?>, options: [Value], profileValue: Value,
         label: @escaping (Value) -> LocalizedStringKey) {
        self.title = title
        _selection = selection
        self.options = options
        self.profileValue = profileValue
        self.label = label
    }

    var body: some View {
        ChoiceRow(title: title, selection: $selection, defaultValue: profileValue,
                  choices: options.map { .init(value: $0, text: Text(label($0))) })
    }
}

/// One Home row's setting: Default (the style the row gets unless set), a style, or
/// Hidden, which leaves the row off Home.
private struct ShelfStylePicker: View {
    @ObservedObject private var layout = HomeLayoutStore.shared
    let shelf: ShelfLayoutInfo

    private enum Setting: Hashable {
        case style(ShelfStyle)
        case hidden
    }

    var body: some View {
        ChoiceRow(title: Text(shelf.title),
                  selection: selection,
                  defaultValue: .style(layout.defaultStyle(for: shelf.id)),
                  choices: ShelfStyle.allCases.map { .init(value: Setting.style($0), text: Text($0.label)) }
                      + [.init(value: .hidden, text: Text("Hidden"))])
    }

    private var selection: Binding<Setting?> {
        Binding {
            layout.isHidden(shelf.id) ? .hidden : layout.shelfStyles[shelf.id].map(Setting.style)
        } set: { setting in
            switch setting {
            case .hidden:
                layout.setHidden(true, for: shelf.id)
            case let .style(style):
                layout.setHidden(false, for: shelf.id)
                layout.setStyle(style, for: shelf.id)
            case nil:
                layout.setHidden(false, for: shelf.id)
                layout.setStyle(nil, for: shelf.id)
            }
        }
    }
}
