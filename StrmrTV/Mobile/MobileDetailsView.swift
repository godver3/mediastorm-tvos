#if os(iOS)
import SwiftUI

/// A title's page on a phone or iPad, laid out like the Expo phone details page: the backdrop
/// with the logo, metadata, ratings and overview, Play / Resume with the secondary actions,
/// the prequeued stream's Audio & Subtitles, then (series) the season chips over the episode
/// carousel, and the collection, More Like This and cast rows. State and playback live in
/// `MobileDetailsModel`; More Options is the navigation bar's menu.
struct MobileDetailsView: View {
    let target: DetailsTarget

    @StateObject var model: MobileDetailsModel
    @ObservedObject var playback = PlaybackCoordinator.shared
    @ObservedObject var spoilers = SpoilerSettingsStore.shared
    @EnvironmentObject var watchlist: WatchlistStore
    @EnvironmentObject var customLists: CustomListsStore
    @EnvironmentObject var titles: TitleStateStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) var sizeClass
    @State var overviewExpanded = false
    @State var actionError: String?
    @State var watchlistBusy = false
    @State var watchedBusy = false

    init(target: DetailsTarget) {
        self.target = target
        _model = StateObject(wrappedValue: MobileDetailsModel(target: target))
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(size: geo.size)
                    VStack(alignment: .leading, spacing: 22) {
                        headerText
                        actionsSection
                        prequeueSection
                        if !target.isMovie { episodesSection }
                        relatedSections
                    }
                    .frame(maxWidth: Self.contentWidth, alignment: .leading)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 32)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
        }
        .background(Color.brandBackground.ignoresSafeArea())
        .navigationTitle(target.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .task { await model.load() }
        .onAppear { playback.prewarm(target) }
        .onChange(of: playback.sessionsEnded) {
            model.prequeueOverrides = (nil, ManualTrackOverrides())
            Task { await model.load() }
        }
        .modifier(MobileDetailsPresentations(model: model))
        .overlay(alignment: .bottom) { toastView }
    }

    static let contentWidth: CGFloat = 760

    // MARK: Hero

    /// Taller than wide on a phone held upright, shorter in landscape so the actions show.
    func heroHeight(_ size: CGSize) -> CGFloat {
        let landscape = size.width > size.height
        return landscape ? max(220, size.height * 0.62) : min(size.width * 1.05, size.height * 0.58)
    }

    private func hero(size: CGSize) -> some View {
        let height = heroHeight(size)
        // The art runs under the side safe areas (landscape notch), the logo stays inside them.
        return Color.clear.frame(width: size.width, height: height).background {
            GeometryReader { geo in
                RemoteImage(url: Artwork.url(model.backdropURL), size: geo.size) { _ in Color.white.opacity(0.05) }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.35), location: 0),
                            .init(color: .clear, location: 0.25),
                            .init(color: .clear, location: 0.5),
                            .init(color: Color.brandBackground, location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    }
            }
            .ignoresSafeArea(edges: .horizontal)
        }
        .overlay(alignment: compact ? .bottom : .bottomLeading) {
            logo
                .padding(.horizontal, 16)
                .frame(maxWidth: compact ? .infinity : Self.contentWidth + 32,
                       alignment: compact ? .center : .leading)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(target.name)
        .accessibilityAddTraits(.isHeader)
    }

    var compact: Bool { sizeClass == .compact }

    @ViewBuilder
    private var logo: some View {
        let logoSize = CGSize(width: compact ? 260 : 340, height: compact ? 90 : 120)
        if let url = Artwork.logoURL(model.title?.logo?.url ?? target.logoURL, size: "w500") {
            RemoteImage(url: url, size: logoSize, contentMode: .fit,
                        alignment: compact ? .bottom : .bottomLeading) { _ in nameText }
                .frame(width: logoSize.width, height: logoSize.height, alignment: compact ? .bottom : .bottomLeading)
        } else {
            nameText
        }
    }

    private var nameText: some View {
        Text(model.title?.name ?? target.name)
            .font(.largeTitle.bold())
            .multilineTextAlignment(compact ? .center : .leading)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
    }

    // MARK: Header text

    private var headerText: some View {
        VStack(alignment: compact ? .center : .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let badge = model.headerBadge {
                    Label(badge.text.uppercased(), systemImage: badge.symbol ?? "calendar")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.15), in: Capsule())
                }
                Text(model.metadataLine).font(.footnote).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(compact ? .center : .leading)
            if let ratings = model.title?.ratings, !ratings.isEmpty {
                MobileRatingsRow(ratings: ratings)
            }
            if let pref = model.contentPreference, pref.audioLanguage?.isEmpty == false || pref.subtitleLanguage?.isEmpty == false {
                HStack(spacing: 8) {
                    if let audio = pref.audioLanguage, !audio.isEmpty {
                        Label(audio.uppercased(), systemImage: "speaker.wave.2.fill")
                    }
                    if let subtitles = pref.subtitleLanguage, !subtitles.isEmpty {
                        Label(subtitles.uppercased(), systemImage: "captions.bubble.fill")
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            if let overview = model.overview {
                Text(overview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(overviewExpanded ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { overviewExpanded.toggle() } }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(overviewExpanded ? "Shows less" : "Shows the full overview")
            }
            if let message = model.loadError ?? actionError ?? model.trailer.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
        .padding(.top, 6)
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast = titles.toast {
            Text(toast)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
#endif
