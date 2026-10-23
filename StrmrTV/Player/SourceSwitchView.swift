import SwiftUI

/// The player's Switch Source list, full screen over the player: the details
/// page's source rows (full release name, resolution / HDR / size / provider / health badges)
/// in rank order, the playing source checked and focused. Choosing another source hands it
/// back; choosing the playing one, or Menu, closes without a change.
struct SourceSwitchView: View {
    struct Row {
        let option: SourceSwitch.Option
        /// nil for the synthetic row standing for a current source the search didn't return.
        let result: SourceResult?
        let health: SourceHealth?
    }

    let heading: String
    let rows: [Row]
    let onPick: (SourceSwitch.Option) -> Void
    let onClose: () -> Void

    @FocusState private var focused: Int?

    private var currentPosition: Int { rows.firstIndex { $0.option.isCurrent } ?? 0 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header.padding(.bottom, 24)
                    ForEach(Array(rows.enumerated()), id: \.offset) { position, row in
                        Button {
                            if row.option.isCurrent { onClose() } else { onPick(row.option) }
                        } label: {
                            label(row)
                        }
                        .buttonStyle(SourceRowStyle())
                        .focused($focused, equals: position)
                        .id(position)
                    }
                }
                .frame(maxWidth: 1500, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
            .scrollClipDisabled()
            .defaultFocus($focused, currentPosition)
            .onAppear {
                proxy.scrollTo(currentPosition, anchor: .center)
                focused = currentPosition
            }
        }
        .background { Color.black.opacity(0.82).ignoresSafeArea() }
        .onExitCommand { onClose() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch Source").font(.title2.weight(.semibold))
            Text(heading).font(.callout).foregroundStyle(.secondary)
            if !rows.contains(where: { !$0.option.isCurrent }) {
                Text("No other sources").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func label(_ row: Row) -> some View {
        if let result = row.result {
            SourceRow(result: result, health: row.health, isCurrent: row.option.isCurrent)
        } else {
            // The playing source, missing from the search: its name and "Playing now".
            VStack(alignment: .leading, spacing: 8) {
                Label("Playing", systemImage: "checkmark.circle.fill").font(.caption2.weight(.bold))
                Text(row.option.title).font(.callout).lineLimit(1)
                Text(row.option.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.vertical, 8)
        }
    }
}

extension SourceSwitchView.Row {
    /// The rows for `options`, each with its search result and latest health.
    static func rows(_ options: [SourceSwitch.Option], results: [SourceResult],
                     health: [Int: SourceHealth]) -> [Self] {
        options.map { option in
            let result = option.resultIndex.flatMap { index in results.first { $0.index == index } }
            return Self(option: option, result: result,
                        health: option.resultIndex.flatMap { health[$0] } ?? result?.health)
        }
    }
}
