import SwiftUI

/// A cast member's portrait, name and character; opens their page.
struct CastCard: View {
    let member: CastMember
    let opens: Bool

    @FocusState private var isFocused: Bool
    private static let size = CGSize(width: 200, height: 300)

    var body: some View {
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: Self.size.height)) {
            Group {
                if opens {
                    NavigationLink(value: PersonRef(id: member.id, name: member.name, profileURL: member.profileUrl)) { photo }
                } else {
                    Button {} label: { photo }
                }
            }
            .buttonStyle(PosterFocusStyle(isFocused: isFocused))
            .focused($isFocused)
            .accessibilityLabel([member.name, member.character].compactMap { $0 }.joined(separator: ", "))

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name).font(.caption.weight(.semibold)).lineLimit(1)
                if let character = member.character, !character.isEmpty {
                    Text(character).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .frame(width: Self.size.width, alignment: .leading)
    }

    private var photo: some View { CastPhoto(url: member.profileUrl, size: Self.size) }
}

/// The Expo watch-state eye: outlined for none, outlined with a filled iris for some,
/// filled for all.
struct WatchStateEye: View {
    enum State { case none, partial, complete }
    let state: State

    var body: some View {
        Image(systemName: state == .complete ? "eye.fill" : "eye")
            .overlay {
                if state == .partial {
                    Circle().frame(width: 9, height: 9)
                }
            }
    }
}

struct SeasonChipStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .foregroundStyle(isFocused ? .black : .white)
            .background(
                Capsule().fill(isFocused ? Color.white : selected ? Color.white.opacity(0.28) : Color.white.opacity(0.08))
            )
            .scaleEffect(isFocused ? 1.08 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct EpisodeCard: View {
    let episode: Episode
    let focus: FocusState<DetailsView.DetailsFocus?>.Binding
    let watched: Bool
    /// Spoiler settings (`SpoilerSettingsStore`): the artwork blurred, the overview hidden.
    var hidesThumbnail = false
    var hidesOverview = false
    let fallbackImage: String?
    let onChooseSource: () -> Void
    let onToggleWatched: () -> Void
    /// The episode has a copy in the profile's libraries (Play uses it).
    var inLibrary = false
    var onChooseVersion: (() -> Void)?
    let action: () -> Void

    /// Marking an episode watched or unwatched clears its progress on the server.
    private var fraction: Double { watched == (episode.watched == true) ? episode.resume.flatMap { $0.eligible ? $0.fraction : nil } ?? 0 : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: PosterFocusStyle.captionSpacing(cardHeight: 225)) {
            Button(action: action) {
                AsyncImage(url: Artwork.url(episode.image?.url ?? fallbackImage, size: "w780")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Rectangle().fill(.quaternary) }
                .frame(width: 400, height: 225)
                // Opaque, so the blur doesn't fade into the page at the edges.
                .blur(radius: hidesThumbnail ? 36 : 0, opaque: true)
                .overlay(alignment: .bottom) {
                    if ProgressBar.shows(fraction) { ProgressBar(fraction: fraction).padding(14) }
                }
                .overlay(alignment: .bottomLeading) {
                    // The Expo episode strip's release date overlay, unreleased episodes too.
                    if let date = Self.airDateText(episode.airedDate) {
                        Text(date)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.leading, 12)
                            .padding(.bottom, ProgressBar.shows(fraction) ? 30 : 12)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let badge = ReleaseBadge.forEpisode(airDate: episode.airedDate) {
                        BadgeLabel(text: badge).padding(12)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if inLibrary {
                        Image(systemName: "externaldrive.fill")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.trailing, 12)
                            .padding(.bottom, ProgressBar.shows(fraction) ? 30 : 12)
                            .accessibilityLabel("In your library")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if watched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.black, .white)
                            .shadow(radius: 4)
                            .padding(12)
                    }
                }
                .clipped()
            }
            .buttonStyle(PosterFocusStyle(isFocused: focus.wrappedValue == .episode(episode.id)))
            .focused(focus, equals: .episode(episode.id))
            .accessibilityLabel("Episode \(episode.episodeNumber), \(episode.name)"
                + (episode.runtimeMinutes.map { $0 > 0 ? ", \($0) minutes" : "" } ?? "") + (watched ? ", watched" : ""))
            .contextMenu {
                Button { action() } label: { Label("Play", systemImage: "play.fill") }
                if let onChooseVersion {
                    Button(action: onChooseVersion) { Label("Choose Version", systemImage: "externaldrive") }
                }
                Button(action: onChooseSource) { Label("Choose Source", systemImage: "list.bullet") }
                Button(action: onToggleWatched) {
                    Label(watched ? "Mark as Unwatched" : "Mark as Watched", systemImage: watched ? "eye.slash" : "eye")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                // The runtime trails the name, so a long name truncates first.
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(episode.episodeNumber). \(episode.name)").font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    if let runtime = formatRuntime(episode.runtimeMinutes) {
                        Text(runtime).font(.caption2).foregroundStyle(.secondary).fixedSize()
                    }
                }
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                        .blur(radius: hidesOverview ? 5 : 0)
                        .accessibilityHidden(hidesOverview)
                }
            }
        }
        .frame(width: 400, alignment: .leading)
    }

    /// The Expo strip's `formatAirDate`: the air day as en-US "Oct 21, 2026", whatever the
    /// device language; nil without a valid date.
    static func airDateText(_ airedDate: String?) -> String? {
        ReleaseBadge.parseDay(airedDate)?.formatted(
            .dateTime.month(.abbreviated).day().year().locale(Locale(identifier: "en_US")))
    }
}
