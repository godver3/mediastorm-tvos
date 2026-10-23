import SwiftUI

/// Full-screen list of a movie's or episode's library copies, best first (the one Play uses),
/// laid out like the source list: where the copy lives, its quality, the file and its size.
struct LibraryVersionsView: View {
    let heading: String
    let versions: [LibraryVersion]
    let backdropURL: String?
    let onPick: (LibraryVersion) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(heading).font(.title2.weight(.semibold))
                    Text(versions.count == 1 ? String(localized: "1 version in your libraries")
                                             : String(localized: "\(versions.count) versions in your libraries"))
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)

                if versions.isEmpty {
                    Text("No library copies").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                        Button {
                            dismiss()
                            onPick(version)
                        } label: {
                            LibraryVersionRow(version: version, playsByDefault: index == 0)
                        }
                        .buttonStyle(SourceRowStyle())
                    }
                }
            }
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        }
        .scrollClipDisabled()
        .background { SourcePickerBackdrop(url: backdropURL) }
        .onExitCommand { dismiss() }
    }
}

/// One copy: its source badge and quality, then the file name and where it lives.
struct LibraryVersionRow: View {
    let version: LibraryVersion
    /// The copy Play picks.
    var playsByDefault = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LibrarySourceBadge(source: version.source)
                Text(version.quality).font(.caption2.weight(.bold))
                if playsByDefault {
                    Label("Play uses this", systemImage: "play.fill").font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(version.item.fileName ?? version.quality).font(.callout).lineLimit(1)
            Text([version.origin, version.size].compactMap { $0 }.joined(separator: "  ·  "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 8)
    }
}

/// "Local" / "Plex" / "Jellyfin" in the Expo badge colours (green, amber, violet).
struct LibrarySourceBadge: View {
    let source: LibrarySource

    var body: some View {
        Text(source.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Capsule().fill(color))
    }

    private var color: Color {
        switch source {
        case .local: Color(red: 0.18, green: 0.80, blue: 0.44)
        case .plex: Color(red: 1.0, green: 0.62, blue: 0.10)
        case .jellyfin: Color(red: 0.42, green: 0.36, blue: 0.91)
        }
    }
}
