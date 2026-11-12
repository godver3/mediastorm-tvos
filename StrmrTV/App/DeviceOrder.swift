import Foundation

/// A device's own order for a list the server (or the app) orders by default: Home's rows,
/// the menu's tabs. Saved as the ids in the order the person set; nothing goes to the server.
enum DeviceOrder {
    /// `defaults` in the saved order. Saved ids that are gone are dropped; an id the saved
    /// order doesn't know (a row added since) goes right after the item that precedes it in
    /// `defaults`, or first when nothing does, so it lands where the server put it.
    static func apply(_ saved: [String], to defaults: [String]) -> [String] {
        guard !saved.isEmpty else { return defaults }
        let known = Set(defaults)
        var seen = Set<String>()
        var result = saved.filter { known.contains($0) && seen.insert($0).inserted }
        for (index, id) in defaults.enumerated() where !seen.contains(id) {
            let anchor = defaults[..<index].last(where: seen.contains)
            let at = anchor.flatMap { result.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            result.insert(id, at: at)
            seen.insert(id)
        }
        return result
    }

    /// `items` in the saved order, by their ids.
    static func apply<T>(_ saved: [String], to items: [T], id: (T) -> String) -> [T] {
        guard !saved.isEmpty else { return items }
        var byID: [String: T] = [:]
        for item in items where byID[id(item)] == nil { byID[id(item)] = item }
        return apply(saved, to: items.map(id)).compactMap { byID[$0] }
    }

    /// `order` with `id` moved to where `target` is now: before it when moving up, after it
    /// when moving down, so the moved item takes the target's place.
    static func move(_ id: String, to target: String, in order: [String]) -> [String] {
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else {
            return order
        }
        var next = order
        next.remove(at: from)
        next.insert(id, at: to)
        return next
    }
}
