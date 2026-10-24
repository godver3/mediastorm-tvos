import SwiftUI

/// Settings › Spoilers rows for this device's overrides (`SpoilerSettingsStore`): each has
/// "Default (…)", the profile's value, then On and Off.
struct SpoilerSettingsRows: View {
    @ObservedObject private var store = SpoilerSettingsStore.shared

    private static let onOff: [ChoiceRow<Bool>.Choice] = [
        .init(value: true, name: String(localized: "On")),
        .init(value: false, name: String(localized: "Off")),
    ]

    var body: some View {
        ChoiceRow(title: "Hide Episode Thumbnails", selection: $store.blurThumbnails,
                  defaultValue: store.server.blurThumbnails ?? false, choices: Self.onOff)
            .accessibilityHint(Text("Blurs the artwork of episodes you haven't reached"))
        if store.blurThumbnails ?? store.server.blurThumbnails ?? false {
            ChoiceRow(title: "Hide Next Episode's Thumbnail", selection: $store.thumbnailsIncludeNext,
                      defaultValue: store.server.thumbnailsIncludeNext ?? false, choices: Self.onOff)
                .accessibilityHint(Text("Also blurs the artwork of the episode you're up to"))
        }
        ChoiceRow(title: "Hide Episode Descriptions", selection: $store.blurOverviews,
                  defaultValue: store.server.blurOverviews ?? false, choices: Self.onOff)
            .accessibilityHint(Text("Hides the descriptions of episodes you haven't reached"))
        if store.blurOverviews ?? store.server.blurOverviews ?? false {
            ChoiceRow(title: "Hide Next Episode's Description", selection: $store.overviewsIncludeNext,
                      defaultValue: store.server.overviewsIncludeNext ?? false, choices: Self.onOff)
                .accessibilityHint(Text("Also hides the description of the episode you're up to"))
        }
    }
}
