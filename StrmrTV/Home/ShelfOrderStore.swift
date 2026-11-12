import Foundation

/// Home's rows in this device's own order (Settings › Home Layout › Row Order), on top of
/// the profile's order. Empty follows the profile. Applies to every Home view; a row the
/// order doesn't name keeps its place after the row before it on the profile
/// (`DeviceOrder.apply`). The promoted Top 10 hero always leads.
@MainActor
final class ShelfOrderStore: ObservableObject {
    static let shared = ShelfOrderStore()

    private let defaults: UserDefaults
    private static let key = "homeLayout.shelfOrder"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _order = Published(initialValue: defaults.stringArray(forKey: Self.key) ?? [])
    }

    /// Row ids in the order set on this device; empty for the profile's order.
    @Published private(set) var order: [String] {
        didSet { defaults.set(order, forKey: Self.key) }
    }

    var isCustom: Bool { !order.isEmpty }

    /// `items` in this device's order.
    func ordered<T>(_ items: [T], id: (T) -> String) -> [T] {
        let sorted = DeviceOrder.apply(order, to: items, id: id)
        let pinned = sorted.filter { id($0) == HomeShelf.promotedTopTenID }
        return pinned + sorted.filter { id($0) != HomeShelf.promotedTopTenID }
    }

    /// Moves `id` to `target`'s place among `shown`, the rows as the editor lists them.
    func move(_ id: String, to target: String, in shown: [String]) {
        order = DeviceOrder.move(id, to: target, in: shown)
    }

    /// Saves `shown` as the order (the phone's drag list hands over the whole list).
    func set(_ shown: [String]) { order = shown }

    func reset() { order = [] }
}
