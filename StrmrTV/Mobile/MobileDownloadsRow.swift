#if os(iOS)
import SwiftUI

/// One download in the list, as the Expo row: the poster, the title (an episode's name under
/// its show), then progress with bytes, speed and time left while it runs, its size once done,
/// or why it is waiting / failed. The trailing symbol says what a tap does (pause, resume,
/// retry, play).
struct MobileDownloadRow: View {
    let item: DownloadItem
    /// Episodes listed under their show leave the show's name out.
    var showsSeries = true

    var body: some View {
        HStack(spacing: 12) {
            MobileDownloadPoster(item: item)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.semibold)).lineLimit(2)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(symbolColor)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint)
    }

    private var title: String {
        guard item.isEpisode else { return item.name }
        return showsSeries ? item.name : item.rowTitle
    }

    private var subtitle: String? {
        guard item.isEpisode else { return item.year.map(String.init) }
        let code = item.episodeCode ?? ""
        guard showsSeries else { return code }
        if let name = item.episodeName, !name.isEmpty { return "\(code) · \(name)" }
        return code
    }

    @ViewBuilder
    private var status: some View {
        switch item.status {
        case .downloading, .paused, .pending:
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: item.progress)
                    .tint(item.status == .downloading ? .accentColor : .secondary)
                Text(progressLine).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        case .completed:
            Label(DownloadFormat.bytes(item.expectedBytes), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
        case .failed:
            Text(item.errorMessage ?? String(localized: "Download failed"))
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var progressLine: String {
        let sizes = item.expectedBytes > 0
            ? "\(DownloadFormat.bytes(item.bytesWritten)) of \(DownloadFormat.bytes(item.expectedBytes))"
            : DownloadFormat.bytes(item.bytesWritten)
        switch item.status {
        case .pending:
            switch item.waitingReason {
            case .wifi: return String(localized: "Waiting for Wi-Fi")
            case .server: return String(localized: "Waiting for the server")
            case nil: return item.bytesWritten > 0 ? String(localized: "Queued · \(sizes)") : String(localized: "Queued")
            }
        case .paused:
            return String(localized: "Paused · \(sizes)")
        default:
            let parts = ["\(Int((item.progress * 100).rounded()))%", sizes, DownloadFormat.speed(item.bytesPerSecond),
                         DownloadFormat.eta(item)]
            return parts.compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var symbol: String {
        switch item.status {
        case .downloading: "pause.circle"
        case .paused: "arrow.down.circle"
        case .pending: "clock"
        case .completed: "play.circle.fill"
        case .failed: "arrow.clockwise.circle"
        }
    }

    private var symbolColor: Color {
        switch item.status {
        case .downloading: .accentColor
        case .completed: .primary
        case .failed: .red
        default: .secondary
        }
    }

    private var hint: String {
        switch item.status {
        case .downloading, .pending: String(localized: "Pauses the download")
        case .paused: String(localized: "Resumes the download")
        case .completed: String(localized: "Plays the download")
        case .failed: String(localized: "Retries the download")
        }
    }
}

/// The poster saved with the download (so it shows offline), else the remote one.
struct MobileDownloadPoster: View {
    let item: DownloadItem
    var size = CGSize(width: 48, height: 72)

    var body: some View {
        RemoteImage(url: DownloadManager.shared.posterFileURL(item) ?? Artwork.url(item.posterURL, size: "w342"),
                    size: size) { _ in
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: item.isMovie ? "film" : "tv").foregroundStyle(.secondary))
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A row's actions: tap, swipe and context menu share them.
enum MobileDownloadActions {
    @MainActor
    static func primary(_ item: DownloadItem, play: (DownloadItem) -> Void) {
        let manager = DownloadManager.shared
        switch item.status {
        case .completed: play(item)
        case .downloading, .pending: manager.pause(item.id)
        case .paused, .failed: manager.resume(item.id)
        }
    }
}
#endif
