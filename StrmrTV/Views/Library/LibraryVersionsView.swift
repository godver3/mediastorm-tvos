import SwiftUI

/// Full-screen list of a movie's or episode's library copies in the server's order (local first;
/// the first is the one autoplay uses), laid out like the source list: where the copy lives, its quality, the
/// file and its size. Opened by Play, it ends with Stream Instead (`onStream`).
struct LibraryVersionsView: View {
    let heading: String
    let versions: [LibraryVersion]
    let backdropURL: String?
    var onStream: (() -> Void)?
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
                    ForEach(versions) { version in
                        Button {
                            dismiss()
                            onPick(version)
                        } label: {
                            LibraryVersionRow(version: version)
                        }
                        .buttonStyle(SourceRowStyle())
                    }
                }
                if let onStream {
                    Button {
                        dismiss()
                        onStream()
                    } label: {
                        Label("Stream Instead", systemImage: "icloud.and.arrow.down")
                            .font(.callout.weight(.semibold))
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(SourceRowStyle())
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                LibrarySourceBadge(source: version.source)
                Text(version.quality).font(.caption2.weight(.bold))
            }
            MarqueeText(text: version.item.fileName ?? version.quality).font(.callout)
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
