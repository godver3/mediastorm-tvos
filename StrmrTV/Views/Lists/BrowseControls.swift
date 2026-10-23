import SwiftUI

/// Sort, filter and random-pick buttons over the grid. Each menu shows its current choice.
struct BrowseControls: View {
    let list: BrowseList
    @Binding var options: BrowseOptions
    /// Genre facets of the loaded list.
    let genres: [String]
    let isPicking: Bool
    let onRandom: (() -> Void)?
    var onRename: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 24) {
            if list.parts.count > 1 {
                Picker("List", selection: $options.part) {
                    ForEach(Array(list.parts.enumerated()), id: \.offset) { Text($1).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if !list.sorts.isEmpty { sortMenu }
            if list.filters {
                kindMenu
                watchMenu
                // Selected genres stay listed even when the filtered list no longer has them.
                let allGenres = Set(genres).union(options.genres).sorted()
                if !allGenres.isEmpty { genreMenu(allGenres) }
                if options.isFiltered {
                    Button {
                        options.kind = nil
                        options.watch = .all
                        options.genres = []
                    } label: {
                        Label("Clear Filters", systemImage: "xmark")
                    }
                }
            }
            Spacer(minLength: 0)
            if let onRandom {
                Button(action: onRandom) {
                    Label("Random", systemImage: "dice")
                }
                .disabled(isPicking)
            }
            if let onRename, let onDelete {
                Menu {
                    Button(action: onRename) { Label("Rename…", systemImage: "pencil") }
                    Button(role: .destructive, action: onDelete) { Label("Delete List…", systemImage: "trash") }
                } label: {
                    Label("Manage", systemImage: "ellipsis").labelStyle(.iconOnly)
                }
                .accessibilityLabel("Manage List")
            }
        }
        .font(.callout)
        .focusSection()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(list.sorts, id: \.self) { sort in
                Button { options.choose(sort) } label: {
                    if sort == options.sort {
                        Label(sort.label, systemImage: sort == .default ? "checkmark" : arrow)
                    } else {
                        Text(sort.label)
                    }
                }
            }
            if list.filters, options.sort == .rating {
                Picker("Rating Source", selection: $options.ratingSource) {
                    ForEach(RatingSource.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
        } label: {
            Label(sortTitle, systemImage: "arrow.up.arrow.down")
        }
    }

    private var arrow: String { options.ascending ? "arrow.up" : "arrow.down" }

    private var sortTitle: String {
        guard options.sort != .default else { return String(localized: "Sort") }
        var title = options.sort.label
        if options.sort == .rating, list.filters { title += " (\(options.ratingSource.label))" }
        return "\(title) \(options.ascending ? "↑" : "↓")"
    }

    private var kindMenu: some View {
        Picker(selection: $options.kind) {
            Text("Movies and Shows").tag(BrowseKind?.none)
            ForEach(BrowseKind.allCases) { Text($0.noun).tag(Optional($0)) }
        } label: {
            Label(options.kind?.noun ?? String(localized: "Movies and Shows"), systemImage: "film")
        }
        .pickerStyle(.menu)
    }

    private var watchMenu: some View {
        Picker(selection: $options.watch) {
            ForEach(WatchFilter.allCases, id: \.self) { Text($0.label).tag($0) }
        } label: {
            Label(options.watch.label, systemImage: "eye")
        }
        .pickerStyle(.menu)
    }

    private func genreMenu(_ all: [String]) -> some View {
        Menu {
            ForEach(all, id: \.self) { genre in
                Button {
                    if options.genres.contains(genre) { options.genres.remove(genre) } else { options.genres.insert(genre) }
                } label: {
                    if options.genres.contains(genre) { Label(genre, systemImage: "checkmark") } else { Text(genre) }
                }
            }
        } label: {
            Label(genreTitle, systemImage: "theatermasks")
        }
    }

    private var genreTitle: String {
        switch options.genres.count {
        case 0: String(localized: "All Genres")
        case 1: options.genres.first!
        default: String(localized: "\(options.genres.count) Genres")
        }
    }
}

/// Jump-to-letter buttons for a list sorted by name: only letters the list has; the
/// chosen one filters the grid to it, and choosing it again shows every letter.
struct LetterIndex: View {
    let letters: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(letters, id: \.self) { letter in
                    VStack(spacing: 10) {
                        Button {
                            selection = selection == letter ? nil : letter
                        } label: {
                            Text(letter).font(.callout.weight(.semibold)).frame(minWidth: 36)
                        }
                        // Marks the chosen letter once focus moves on (an unfocused
                        // prominent button looks like any other on tvOS).
                        Circle().frame(width: 8, height: 8).opacity(selection == letter ? 1 : 0)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .focusSection()
    }
}
