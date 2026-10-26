import SwiftUI

/// How a rating source is drawn: its icon (served by the server under
/// `/api/static/rating_icons`), its colour and the score text. Mirrors the Expo details page.
struct RatingStyle: Equatable {
    let label: String
    let colorHex: String
    /// The icon's file name, nil for a source the server has no icon for (a star then).
    let icon: String?
    let text: String

    /// Expo's order: IMDb, TMDB, Trakt, RT critics, RT audience, Metacritic, Letterboxd.
    static let order = ["imdb", "tmdb", "trakt", "tomatoes", "audience", "metacritic", "letterboxd"]

    static func sorted(_ ratings: [Rating]) -> [Rating] {
        ratings.enumerated().sorted { a, b in
            let ia = order.firstIndex(of: a.element.source) ?? order.count
            let ib = order.firstIndex(of: b.element.source) ?? order.count
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
    }

    init(label: String, colorHex: String, icon: String?, text: String) {
        self.label = label
        self.colorHex = colorHex
        self.icon = icon
        self.text = text
    }

    init(_ rating: Rating) {
        let text = Self.format(rating)
        switch rating.source {
        case "imdb": self.init(label: "IMDb", colorHex: "#F5C518", icon: "imdb.png", text: text)
        case "tmdb": self.init(label: "TMDB", colorHex: "#01D277", icon: "tmdb.png", text: text)
        case "trakt": self.init(label: "Trakt", colorHex: "#ED1C24", icon: "trakt.png", text: text)
        case "letterboxd": self.init(label: "Letterboxd", colorHex: "#00E054", icon: "letterboxd.png", text: text)
        case "tomatoes":
            // Fresh at 60% and up, on either scale.
            let percent = rating.max == 100 ? rating.value : rating.value * 10
            if percent >= 60 {
                self.init(label: "Rotten Tomatoes", colorHex: "#FA320A", icon: "rt_critics.png", text: text)
            } else {
                self.init(label: "Rotten Tomatoes", colorHex: "#6B8E23", icon: "rt_rotten.png", text: text)
            }
        case "audience": self.init(label: "RT Audience", colorHex: "#FA320A", icon: "rt_audience.png", text: text)
        case "metacritic": self.init(label: "Metacritic", colorHex: "#FFCC34", icon: "metacritic.png", text: text)
        default: self.init(label: rating.source, colorHex: "#888888", icon: nil, text: text)
        }
    }

    /// IMDb and Letterboxd as decimals ("7.5", "3.5"); the percentage sources as "87%";
    /// anything else by its scale.
    static func format(_ rating: Rating) -> String {
        switch rating.source {
        case "imdb", "letterboxd": String(format: "%.1f", rating.value)
        case "tmdb", "trakt", "tomatoes", "audience", "metacritic": "\(Int(rating.value.rounded()))%"
        default: rating.max == 10 ? String(format: "%.1f", rating.value) : "\(Int(rating.value.rounded()))%"
        }
    }
}

/// The details header's ratings line: one icon and score per source.
struct RatingsRow: View {
    let ratings: [Rating]

    var body: some View {
        HStack(spacing: 30) {
            ForEach(RatingStyle.sorted(ratings), id: \.source) { rating in
                let style = RatingStyle(rating)
                HStack(spacing: 10) {
                    RemoteImage(url: style.icon.flatMap { ServerArtwork.url("/api/static/rating_icons/\($0)") },
                                size: CGSize(width: 32, height: 32), contentMode: .fit) { _ in
                        Image(systemName: "star.fill").font(.system(size: 24)).foregroundStyle(style.color)
                    }
                    Text(style.text).font(.system(size: 26, weight: .semibold)).foregroundStyle(style.color)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(style.label) \(style.text)")
            }
        }
    }
}

extension RatingStyle {
    var color: Color { Color(hex: colorHex) ?? .secondary }
}
