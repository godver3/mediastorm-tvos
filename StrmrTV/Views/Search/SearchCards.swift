import SwiftUI

/// A person in the search results: their photo with the name under it, opening the person
/// page (Expo's actor result). No long-press menu, as in Expo.
struct PersonCard: View {
    let person: PersonRef
    var width: CGFloat = PosterCard.width
    @FocusState private var isFocused: Bool

    init?(title: Title, width: CGFloat = PosterCard.width) {
        guard title.mediaType == "person", let tmdbID = title.tmdbId else { return nil }
        person = PersonRef(id: tmdbID, name: title.name, profileURL: title.poster?.url)
        self.width = width
    }

    private var height: CGFloat { width * PosterCard.height / PosterCard.width }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: height)) {
            NavigationLink(value: person) {
                CastPhoto(url: person.profileURL, size: CGSize(width: width, height: height))
            }
            .buttonStyle(PosterFocusStyle(isFocused: isFocused))
            .focused($isFocused)
            .accessibilityLabel(person.name)

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name).font(.caption.weight(.semibold)).lineLimit(1)
                Text("Person").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// One entry in the rail beside the results: a suggested query.
struct SearchRailButton: View {
    let label: String
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.weight(isFocused ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(isFocused ? Color.black : Color.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Capsule().fill(isFocused ? Color.white : Color.clear))
        }
        .buttonStyle(RailButtonStyle())
        .focused($isFocused)
    }
}

/// No system highlight: the pill above draws focus.
private struct RailButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
