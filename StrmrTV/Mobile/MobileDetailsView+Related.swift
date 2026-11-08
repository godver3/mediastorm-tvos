#if os(iOS)
import SwiftUI

/// Under the actions: the library copy or prequeued stream Play will use (with its Audio &
/// Subtitles), and the collection, More Like This and cast rows.
extension MobileDetailsView {
    // MARK: Prequeue / library line

    @ViewBuilder
    var prequeueSection: some View {
        let versions = model.primaryVersions
        if let best = versions.first {
            Label(versions.count == 1
                  ? "\(best.source.label) · \(best.quality)"
                  : String(localized: "\(versions.count) versions · \(best.source.label) · \(best.quality)"),
                  systemImage: "externaldrive.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let warm = model.warmPrequeue {
            if let status = warm.status {
                VStack(alignment: .leading, spacing: 8) {
                    if let release = status.releaseTitle {
                        Text(release)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let summary = model.tracksSummary {
                        Button { model.showTracks() } label: {
                            HStack(spacing: 12) {
                                Label(summary.audio, systemImage: "speaker.wave.2.fill")
                                Label(summary.subtitles, systemImage: "captions.bubble.fill")
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .font(.caption)
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Audio & Subtitles: \(summary.audio), subtitles \(summary.subtitles)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding a source…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Related rows

    @ViewBuilder
    var relatedSections: some View {
        if let collection = model.title?.collection, !model.collectionMovies.isEmpty {
            relatedRow(String(localized: "Part of \(collection.name)")) {
                ForEach(model.collectionMovies) { MobilePosterTile(title: $0, opens: !model.isKids) }
            }
        }
        if !model.similar.isEmpty {
            relatedRow(String(localized: "More Like This")) {
                ForEach(model.similar.prefix(20)) { MobilePosterTile(title: $0, opens: !model.isKids) }
            }
        }
        if !model.cast.isEmpty {
            relatedRow(String(localized: "Cast")) {
                ForEach(model.cast, id: \.id) { MobileCastTile(member: $0, opens: !model.isKids) }
            }
        }
    }

    private func relatedRow<Cards: View>(_ heading: String, @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) { cards() }
                    .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }
}

/// A poster that opens the title's page (kids profiles don't navigate from related rows).
struct MobilePosterTile: View {
    let title: Title
    var opens = true
    var width: CGFloat = 116

    var body: some View {
        if opens {
            NavigationLink(value: DetailsTarget(title)) { poster }.buttonStyle(.plain)
        } else {
            poster
        }
    }

    private var poster: some View {
        let size = CGSize(width: width, height: width * 1.5)
        return VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: Artwork.url(title.poster?.url, size: "w342"), size: size) { _ in
                ZStack {
                    Color.white.opacity(0.08)
                    Text(title.name).font(.caption).multilineTextAlignment(.center).padding(6)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title.name).font(.caption.weight(.semibold)).lineLimit(1)
            if let year = title.year {
                Text(String(year)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size.width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A cast member's round portrait, name and character; opens their page.
struct MobileCastTile: View {
    let member: CastMember
    let opens: Bool

    var body: some View {
        if opens {
            NavigationLink(value: PersonRef(id: member.id, name: member.name, profileURL: member.profileUrl)) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(spacing: 6) {
            CastPhoto(url: member.profileUrl, size: CGSize(width: 84, height: 84))
                .frame(width: 84, height: 84)
                .clipShape(Circle())
            Text(member.name).font(.caption.weight(.semibold)).lineLimit(1)
            if let character = member.character, !character.isEmpty {
                Text(character).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 92)
        .multilineTextAlignment(.center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The ratings line: one icon and score per source, in the Expo order.
struct MobileRatingsRow: View {
    let ratings: [Rating]

    var body: some View {
        // One line, scrolling only when the scores don't fit.
        ViewThatFits(in: .horizontal) {
            scores
            ScrollView(.horizontal) { scores }.scrollIndicators(.hidden)
        }
    }

    private var scores: some View {
        HStack(spacing: 14) {
            ForEach(RatingStyle.sorted(ratings), id: \.source) { rating in
                let style = RatingStyle(rating)
                HStack(spacing: 5) {
                    RemoteImage(url: style.icon.flatMap { ServerArtwork.url("/api/static/rating_icons/\($0)") },
                                size: CGSize(width: 18, height: 18), contentMode: .fit) { _ in
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(style.color)
                    }
                    .frame(width: 18, height: 18)
                    Text(style.text).font(.footnote.weight(.semibold)).foregroundStyle(style.color)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(style.label) \(style.text)")
            }
        }
        .fixedSize()
    }
}
#endif
