import Foundation

/// A JSON array decoded item by item: an item that fails to decode is skipped (and
/// logged once, with its coding path) instead of failing the whole list, and a `null`
/// or missing array decodes as empty. Go encodes an empty slice as `null`, so a list
/// endpoint with nothing to return (a Continue Watching emptied by a hide) answers `null`.
struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(_ elements: [Element] = []) { self.elements = elements }

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        guard !single.decodeNil() else { elements = []; return }
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        if let count = container.count { elements.reserveCapacity(count) }
        while !container.isAtEnd {
            let index = container.currentIndex
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                // Step past the bad item; `decode` doesn't advance when it throws.
                _ = try? container.decode(Skipped.self)
                Self.log.error("skipped \(Element.self) #\(index): \(Self.describe(error))")
            }
        }
        self.elements = elements
    }

    private static var log: AppLog { AppLog(category: "decode") }

    /// "keyNotFound seriesTitle at [2]" style: enough to find the bad field.
    static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return "\(error)" }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case let .keyNotFound(key, context): return "keyNotFound \(key.stringValue) at \(path(context))"
        case let .valueNotFound(type, context): return "valueNotFound \(type) at \(path(context))"
        case let .typeMismatch(type, context): return "typeMismatch \(type) at \(path(context))"
        case let .dataCorrupted(context): return "dataCorrupted at \(path(context)): \(context.debugDescription)"
        @unknown default: return "\(error)"
        }
    }

    /// Decodes any JSON value, to move an unkeyed container past an item.
    private struct Skipped: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

extension LossyArray: Sendable where Element: Sendable {}

extension KeyedDecodingContainer {
    /// A lossy list field: missing or `null` is empty, bad items are skipped.
    func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent(LossyArray<T>.self, forKey: key)?.elements ?? []
    }
}

extension DisplayListPage {
    private enum CodingKeys: String, CodingKey { case items, total, sourceTotal, genres, alphabetBuckets }

    /// Items decode lossily (a `null` page is empty, a bad item is skipped and logged).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeLossyArray(Item.self, forKey: .items)
        total = try c.decodeIfPresent(Int.self, forKey: .total) ?? items.count
        sourceTotal = try c.decodeIfPresent(Int.self, forKey: .sourceTotal)
        genres = try c.decodeIfPresent([String].self, forKey: .genres)
        alphabetBuckets = try c.decodeIfPresent([String].self, forKey: .alphabetBuckets)
    }
}
