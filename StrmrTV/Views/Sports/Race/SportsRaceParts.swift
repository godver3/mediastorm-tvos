import SwiftUI

/// A sports page's status note (Expo `SportsNotice`): what is missing or late and why, a spinner
/// while it loads, and Try Again when a retry can help.
struct SportsNotice: View {
    let title: String
    let message: String
    var loading = false
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 24) {
            if loading { ProgressView() }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button("Try Again", action: retry).font(.caption) }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 2))
        .focusSection()
    }
}

/// A labelled figure: the label small and muted over the value.
struct SportsFigure: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit().lineLimit(1)
        }
    }
}

/// An inline reading, "LAST 1:23.100": the label muted, the value set off in semibold.
struct SportsReading: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        (Text("\(label) ").foregroundStyle(.secondary) + Text(value).fontWeight(.semibold))
            .font(.caption2).monospacedDigit().lineLimit(1)
    }
}

/// A table's column heading: small, muted capitals.
struct SportsColumnHeading: View {
    let text: String
    var alignment: Alignment = .leading

    init(_ text: String, alignment: Alignment = .leading) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// A small accent heading over a guide ("CIRCUIT GUIDE").
struct SportsEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).kerning(1.5).foregroundStyle(SportsStatusPill.accent)
    }
}

extension String {
    /// "Driver" from "driver": the race page's nouns as titles.
    var sportsCapitalized: String { prefix(1).uppercased() + dropFirst() }
}
