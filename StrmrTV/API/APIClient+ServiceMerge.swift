import Foundation

/// A streaming service's All part, as the Expo app shows a service: its lists (top movies,
/// top shows) merged, one title from each in turn, a list that runs out dropping from the
/// turn. The server sorts and filters each list on its own, so a sort orders each list
/// within the merge rather than the whole.
extension APIClient {
    func mergedServicePage(_ list: BrowseList, options: BrowseOptions, sources: Int, limit: Int, offset: Int,
                           extra: [String: String]) async throws -> BrowsePage {
        let parts = (1...sources).map { part in
            var options = options
            options.part = part
            return options
        }
        let keys = parts.map { Self.totalKey(list, $0, extra) }
        var firstPages: [BrowsePage]?
        var totals = await MergedTotals.shared.totals(keys)
        if offset == 0 || totals == nil {
            // Each list's first page gives its total, and holds every title the merged
            // first page needs.
            let pages = try await fetchAll(parts.map { (list, $0, max(limit, 1), 0, extra) })
            await MergedTotals.shared.store(keys, pages.map(\.total))
            totals = pages.map(\.total)
            firstPages = pages
        }
        guard let totals else { return BrowsePage(entries: [], total: 0) }

        let window = Self.interleave(totals: totals, offset: offset, limit: limit)
        let pages: [BrowsePage]
        if let firstPages, offset == 0 {
            pages = firstPages
        } else {
            pages = try await fetchAll(window.ranges.enumerated().map { index, range in
                (list, parts[index], range.count, range.start, extra)
            })
        }
        // The window's sources in turn; a list that returned fewer titles than its total
        // promised is skipped once it runs out.
        var cursors = Array(repeating: 0, count: sources)
        var entries: [BrowseEntry] = []
        for source in window.order {
            let page = pages[source].entries
            guard cursors[source] < page.count else { continue }
            entries.append(page[cursors[source]])
            cursors[source] += 1
        }
        return BrowsePage(entries: entries, total: totals.reduce(0, +),
                          genres: Set(pages.flatMap(\.genres)).sorted(),
                          letters: Set(pages.flatMap(\.letters)).sorted())
    }

    /// The sources of the merged positions `offset..<offset + limit`, in order, and the
    /// contiguous run of each source's own titles they cover.
    static func interleave(totals: [Int], offset: Int, limit: Int) -> (order: [Int], ranges: [(start: Int, count: Int)]) {
        var order: [Int] = []
        var ranges = totals.map { _ in (start: 0, count: 0) }
        var position = 0
        var round = 0
        let end = offset + limit
        while position < end, totals.contains(where: { $0 > round }) {
            for (source, total) in totals.enumerated() where total > round {
                if position >= end { break }
                if position < offset {
                    ranges[source].start += 1
                } else {
                    order.append(source)
                    ranges[source].count += 1
                }
                position += 1
            }
            round += 1
        }
        return (order, ranges)
    }

    /// Fetches the lists' pages at once, without a task group (Swift 6.4 miscompiles
    /// group results carrying strings).
    private func fetchAll(_ requests: [(BrowseList, BrowseOptions, Int, Int, [String: String])]) async throws -> [BrowsePage] {
        let tasks = requests.map { list, options, limit, offset, extra in
            Task { () throws -> BrowsePage in
                guard limit > 0 else { return BrowsePage(entries: [], total: 0) }
                return try await self.browsePage(list, options: options, limit: limit, offset: offset, extra: extra)
            }
        }
        var pages: [BrowsePage] = []
        for task in tasks { pages.append(try await task.value) }
        return pages
    }

    private static func totalKey(_ list: BrowseList, _ options: BrowseOptions, _ extra: [String: String]) -> String {
        list.query.merging(options.query(for: list)) { _, new in new }.merging(extra) { _, new in new }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    }
}

/// Each merged list's total under the sort and filters it was last read with, so later
/// pages know where every list's titles fall.
private actor MergedTotals {
    static let shared = MergedTotals()
    private var totals: [String: Int] = [:]

    func totals(_ keys: [String]) -> [Int]? {
        let found = keys.compactMap { totals[$0] }
        return found.count == keys.count ? found : nil
    }

    func store(_ keys: [String], _ values: [Int]) {
        for (key, value) in zip(keys, values) { totals[key] = value }
    }
}
