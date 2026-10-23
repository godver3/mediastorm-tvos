import Foundation
import TVServices

/// Shows the app's Continue Watching and Watchlist snapshot on the Apple TV home screen.
/// The app writes the snapshot (see `TopShelfSync`) and asks the system to reload this.
final class TopShelfContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        guard let payload = TopShelfStore.read() else {
            writeStatus("no_payload")
            return completionHandler(nil)
        }
        let sections = payload.sections.compactMap(collection)
        writeStatus(sections.isEmpty ? "no_sections" : "content_ready",
                    counts: sections.map(\.items.count))
        completionHandler(sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections))
    }

    private func collection(_ section: TopShelfPayload.Section) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        let items = section.items.compactMap(item)
        guard !items.isEmpty else { return nil }
        let collection = TVTopShelfItemCollection(items: items)
        collection.title = section.title
        return collection
    }

    private func item(_ payload: TopShelfPayload.Item) -> TVTopShelfSectionedItem? {
        guard let display = URL(string: payload.displayURL) else { return nil }
        let item = TVTopShelfSectionedItem(identifier: payload.id)
        item.title = payload.title
        item.imageShape = switch payload.imageShape {
        case "hdtv": .hdtv
        case "square": .square
        default: .poster
        }
        item.displayAction = TVTopShelfAction(url: display)
        item.playAction = TVTopShelfAction(url: payload.playURL.flatMap(URL.init(string:)) ?? display)
        if let progress = payload.playbackProgress, progress > 0 {
            item.playbackProgress = min(progress, 1)
        }
        if let image = payload.imageURL.flatMap(URL.init(string:)) {
            item.setImageURL(image, for: [.screenScale1x, .screenScale2x])
        }
        return item
    }

    private func writeStatus(_ stage: String, counts: [Int] = []) {
        TopShelfStore.defaults?.set([
            "stage": stage,
            "itemCounts": counts,
            "timestamp": ISO8601DateFormatter().string(from: .now),
        ], forKey: TopShelfStore.statusKey)
    }
}
