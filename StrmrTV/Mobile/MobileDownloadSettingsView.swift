#if os(iOS)
import SwiftUI

/// Settings › Downloads (also the Downloads list's gear): the Expo screen's preferences —
/// Wi-Fi only, simultaneous downloads, delete watched, keep the screen on — with the storage
/// the downloads use and Delete All Downloads.
struct MobileDownloadSettingsView: View {
    @ObservedObject private var settings = DownloadSettings.shared
    @ObservedObject private var manager = DownloadManager.shared
    @State private var confirmingDeleteAll = false

    var body: some View {
        Form {
            Section {
                Toggle("Wi-Fi Only", isOn: $settings.wifiOnly)
            } footer: {
                Text("Downloads wait for Wi-Fi instead of using cellular data. Running downloads pause when Wi-Fi drops and continue when it is back.")
            }
            Section {
                Stepper(value: $settings.maxConcurrent, in: 1...3) {
                    LabeledContent("Simultaneous Downloads", value: "\(settings.maxConcurrent)")
                }
            } footer: {
                Text("More at once can be slower for each; the rest wait in the queue.")
            }
            Section {
                Toggle("Delete Watched Downloads", isOn: $settings.deleteWatched)
            } footer: {
                Text("Finished downloads you have watched are removed the next time Downloads opens while the server is reachable.")
            }
            Section {
                Toggle("Keep Screen On", isOn: $settings.keepScreenAwake)
            } footer: {
                Text("Keeps the screen from locking while a download runs with the app open, for the fastest transfer.")
            }
            Section("Storage") {
                MobileDownloadsStorage(used: manager.usedBytes)
                LabeledContent("Downloads", value: "\(manager.items.count)")
                Button("Delete All Downloads", role: .destructive) { confirmingDeleteAll = true }
                    .disabled(manager.items.isEmpty)
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { manager.refreshUsage() }
        .confirmationDialog("Delete all downloads?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete \(manager.items.count) Downloads", role: .destructive) {
                manager.delete(manager.items.map(\.id))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every downloaded file is removed from this device, and running downloads are cancelled.")
        }
    }
}
#endif
