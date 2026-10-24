import SwiftUI

/// Choose Source for a channel that is a Stremio addon's stream list (Expo's long-press
/// "Choose Source"): the addon's streams, one of which is then tuned with `stremioStreamIndex`.
struct LiveSourceChoice: Identifiable {
    let channel: LiveChannel
    let streams: [LiveStremioStream]

    var id: String { channel.id }

    func channel(streamIndex: Int) -> LiveChannel {
        var picked = channel
        picked.stremioStreamIndex = streamIndex
        return picked
    }
}

extension LiveStore {
    /// Loads the channel's streams and opens the list when there is more than one; otherwise
    /// says why not, with the Expo app's wording.
    func chooseSource(_ channel: LiveChannel) {
        guard sourceChoiceTask == nil else { return }
        show(notice: String(localized: "Loading sources…"), clearing: false)
        sourceChoiceTask = Task {
            defer { sourceChoiceTask = nil }
            do {
                let streams = try await APIClient.shared.liveStremioStreams(channel)
                guard !Task.isCancelled else { return }
                if streams.count > 1 {
                    notice = nil
                    sourceChoice = LiveSourceChoice(channel: channel, streams: streams)
                } else {
                    show(notice: streams.isEmpty ? String(localized: "No playable sources found.")
                        : String(localized: "Only one source is available."))
                }
            } catch {
                if !(error is CancellationError) { show(notice: error.localizedDescription) }
            }
        }
    }

    private func show(notice text: String, clearing: Bool = true) {
        notice = text
        noticeClear?.cancel()
        guard clearing else { return }
        noticeClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// The streams of one Stremio channel, in the addon's order. Picking one closes the list;
/// the presenter tunes it once it is gone.
struct LiveSourceChoicePicker: View {
    let choice: LiveSourceChoice
    let onPick: (LiveStremioStream) -> Void

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 28) {
                    ChannelLogo(channel: choice.channel, size: CGSize(width: 160, height: 90), namesChannel: false)
                        .frame(width: 160, height: 90)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(choice.channel.name).font(.title2.weight(.semibold))
                        Text("Choose stream source").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 24)
                ForEach(choice.streams) { stream in
                    Button { onPick(stream) } label: { row(stream) }
                        .accessibilityIdentifier("live-source-\(stream.index)")
                }
            }
            .padding(80)
        }
        .background { SourcePickerBackdrop(url: nil) }
    }

    private func row(_ stream: LiveStremioStream) -> some View {
        HStack(spacing: 24) {
            Image(systemName: "play.circle").font(.title3).foregroundStyle(.secondary)
            // The label is the whole release line (Expo shows it in full); wrap rather than truncate.
            Text(stream.label).font(.headline).lineLimit(3).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
