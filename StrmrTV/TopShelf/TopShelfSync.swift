import Foundation
import TVServices

/// Writes the Continue Watching and Watchlist snapshot the Top Shelf extension shows, as
/// the Expo app's `TVTopShelfSync` does: poster art, select opens details, play resumes.
/// Only rewrites (and asks the system to reload the shelf) when the snapshot changed.
@MainActor
enum TopShelfSync {
    private static let log = AppLog(category: "topshelf")
    /// The system shelf scrolls; more than this is noise on a home screen.
    static let maxItemsPerSection = 10
    private static var last: TopShelfPayload?

    static func update(continueWatching: [ContinueWatchingItem], watchlist: [WatchlistItem]) {
        let continueSection = TopShelfPayload.Section(
            id: "continue-watching", title: String(localized: "Continue Watching"),
            items: continueWatching.prefix(maxItemsPerSection).map { item in
                let target = DetailsTarget(item)
                return entry(id: item.seriesId, title: title(item), target: target,
                             progress: item.resume?.eligible == true ? item.resume?.fraction : nil)
            })
        let watchlistSection = TopShelfPayload.Section(
            id: "watchlist", title: String(localized: "Watchlist"),
            items: watchlist.prefix(maxItemsPerSection).map { item in
                entry(id: "\(item.mediaType):\(item.id)", title: item.name, target: DetailsTarget(item), progress: nil)
            })
        let payload = TopShelfPayload(sections: [continueSection, watchlistSection].filter { !$0.items.isEmpty })
        guard payload != last else { return }
        guard let defaults = TopShelfStore.defaults else {
            log.error("no App Group defaults (\(TopShelfStore.appGroup)); check the entitlement")
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(payload), forKey: TopShelfStore.payloadKey)
            last = payload
            log.info("wrote \(payload.sections.map { "\($0.id)=\($0.items.count)" }.joined(separator: ", "))")
            TVTopShelfContentProvider.topShelfContentDidChange()
        } catch {
            log.error("encode failed: \(error.localizedDescription)")
        }
    }

    /// Signed out or switching profile: the shelf goes back to the app's static art.
    static func clear() {
        last = nil
        guard let defaults = TopShelfStore.defaults, defaults.data(forKey: TopShelfStore.payloadKey) != nil else { return }
        defaults.removeObject(forKey: TopShelfStore.payloadKey)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    private static func title(_ item: ContinueWatchingItem) -> String {
        guard let ep = item.nextEpisode else { return item.seriesTitle }
        return String(format: "%@ · S%02dE%02d", item.seriesTitle, ep.seasonNumber, ep.episodeNumber)
    }

    private static func entry(id: String, title: String, target: DetailsTarget, progress: Double?) -> TopShelfPayload.Item {
        // Poster with its title text: the shelf draws captions only on focus.
        let image = Artwork.url(target.displayPosterURL ?? target.backdropURL, size: "w500")
        return TopShelfPayload.Item(
            id: id, title: title, imageShape: "poster",
            imageURL: image?.absoluteString,
            displayURL: DeepLink(action: .details, target: target).url?.absoluteString ?? "\(DeepLink.scheme)://",
            playURL: DeepLink(action: .play, target: target).url?.absoluteString,
            playbackProgress: progress)
    }
}
