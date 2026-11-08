#if os(iOS)
import SwiftUI

/// Home on a phone: the profile's shelves from the shared `HomeStore`, each a horizontally
/// scrolling row. Continue Watching (and rows without posters) use landscape art, the rest
/// posters. Tapping a title pushes its details page.
struct MobileHomeView: View {
    @ObservedObject var store: HomeStore
    @ObservedObject private var playback = PlaybackCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if let first = firstHero { MobileHomeHero(card: first) }
                ForEach(store.slots) { slot in
                    switch slot {
                    case let .shelf(shelf) where !shelf.cards.isEmpty:
                        MobileShelfRow(shelf: shelf)
                    case let .loading(_, title):
                        MobileShelfPlaceholder(title: title)
                    default:
                        EmptyView()
                    }
                }
                if let error = store.loadError, store.slots.isEmpty {
                    VStack(spacing: 12) {
                        Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await store.load() } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.load() }
        .navigationTitle("Home")
        .toolbarTitleDisplayMode(.inlineLarge)
        .task {
            if store.slots.isEmpty {
                await store.load()
            } else {
                store.activate()
                await store.refreshIfStale()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfStale() } }
        }
        .onChange(of: playback.sessionsEnded) { Task { await store.reloadPlaybackRows() } }
    }

    /// The first card of the first loaded row, as a large tile at the top of the page.
    private var firstHero: HomeCard? {
        for slot in store.slots {
            if case let .shelf(shelf) = slot, let card = shelf.shown.first(where: { $0.target != nil }) { return card }
        }
        return nil
    }
}

private struct MobileHomeHero: View {
    let card: HomeCard

    var body: some View {
        if let target = card.target {
            NavigationLink(value: target) {
                GeometryReader { geo in
                    RemoteImage(url: Artwork.url(card.backdropURL ?? card.artworkURL), size: geo.size) { _ in
                        Color.white.opacity(0.08)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            if let logo = Artwork.logoURL(card.logoURL, size: "w500") {
                                RemoteImage(url: logo, size: CGSize(width: 220, height: 70), contentMode: .fit,
                                            alignment: .bottomLeading) { _ in
                                    Text(card.title).font(.title2.bold())
                                }
                                .frame(width: 220, height: 70, alignment: .bottomLeading)
                            } else {
                                Text(card.title).font(.title2.bold())
                            }
                            Text(card.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(16)
                    }
                    .overlay(alignment: .bottom) {
                        if card.progress > 0 { MobileProgressBar(value: card.progress).padding(.horizontal, 16).padding(.bottom, 6) }
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }
}

struct MobileShelfRow: View {
    let shelf: HomeShelf

    private var landscape: Bool {
        shelf.id == HomeShelf.continueWatchingID
            || shelf.shown.filter { $0.posterURL != nil }.count < shelf.shown.count / 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(shelf.title).font(.title3.weight(.semibold)).padding(.horizontal, 16)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.shown) { card in
                        if let target = card.target {
                            NavigationLink(value: target) { MobileCard(card: card, landscape: landscape) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct MobileCard: View {
    let card: HomeCard
    let landscape: Bool

    private var size: CGSize { landscape ? CGSize(width: 240, height: 135) : CGSize(width: 116, height: 174) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: Artwork.url(landscape ? card.artworkURL : (card.posterURL ?? card.artworkURL), size: "w500"),
                        size: size) { _ in
                ZStack {
                    Color.white.opacity(0.08)
                    Text(card.title).font(.caption).multilineTextAlignment(.center).padding(6)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .bottom) {
                if card.progress > 0 { MobileProgressBar(value: card.progress).padding(.horizontal, 8).padding(.bottom, 6) }
            }
            if landscape {
                Text(card.title).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(card.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: size.width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct MobileProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(Color.white).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 4)
    }
}

private struct MobileShelfPlaceholder: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.weight(.semibold)).padding(.horizontal, 16)
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)).frame(width: 116, height: 174)
                }
            }
            .padding(.horizontal, 16)
        }
        .redacted(reason: .placeholder)
    }
}
#endif
