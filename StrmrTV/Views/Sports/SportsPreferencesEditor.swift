import Foundation

/// One change to the profile's sports preferences, saved at once over the revision read. A 409
/// means another device saved first: the saved document is reloaded (and the change dropped).
enum SportsPreferencesSave {
    enum Outcome {
        case saved(SportsPreferencesEnvelope)
        /// Another device saved first; the reloaded document, nil when it couldn't be read.
        case conflict(SportsPreferencesEnvelope?)
        case failed(String)
    }

    static let conflictMessage = String(localized: "Another device changed these. Reloaded the saved list.")

    /// `base` with `edit` applied; every other field (and the revision) as read.
    static func edited(_ base: SportsPreferencesEnvelope, _ edit: (inout SportsPreferences) -> Void) -> SportsPreferencesEnvelope {
        var next = base
        edit(&next.preferences)
        return next
    }

    @MainActor
    static func save(_ next: SportsPreferencesEnvelope) async -> Outcome {
        do {
            return .saved(try await APIClient.shared.saveSportsPreferences(next))
        } catch let APIError.http(failure) where failure.status == 409 {
            return .conflict(try? await APIClient.shared.sportsPreferences())
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// Customize's copy of the preferences, shared by its pages (competitions, teams, Add Team).
/// A change shows at once and is saved; a failure puts back what was saved and says why.
@MainActor
final class SportsPreferencesEditor: ObservableObject {
    @Published private(set) var envelope: SportsPreferencesEnvelope?
    @Published private(set) var loading = true
    @Published private(set) var saving = false
    @Published var message: String?
    /// League standings asked for here (team names and Add Team), by league; nil entry: unavailable.
    @Published private(set) var standings: [String: [SportsLeagueTable]] = [:]

    private let onSaved: (SportsPreferencesEnvelope) -> Void

    init(onSaved: @escaping (SportsPreferencesEnvelope) -> Void) {
        self.onSaved = onSaved
    }

    var teamIDs: [String] { envelope?.preferences.teamIds ?? [] }

    func reload() async {
        envelope = try? await APIClient.shared.sportsPreferences()
        loading = false
    }

    func change(_ edit: (inout SportsPreferences) -> Void) async {
        guard let base = envelope, !saving else { return }
        let next = SportsPreferencesSave.edited(base, edit)
        envelope = next
        saving = true
        defer { saving = false }
        switch await SportsPreferencesSave.save(next) {
        case let .saved(saved):
            envelope = saved
            message = nil
            onSaved(saved)
        case let .conflict(reloaded):
            message = SportsPreferencesSave.conflictMessage
            envelope = reloaded ?? base
            if let reloaded { onSaved(reloaded) }
        case let .failed(text):
            envelope = base
            message = text
        }
    }

    func setTeam(league: String, teamID: String, followed: Bool) async {
        await change { $0 = SportsTeamFollows.setting($0, league: league, teamID: teamID, followed: followed) }
    }

    /// The league's standings, fetched once; empty when unavailable.
    func loadStandings(_ league: String) async {
        guard standings[league] == nil else { return }
        let answer = try? await APIClient.shared.sportsStandings(league)
        guard !Task.isCancelled else { return }
        standings[league] = answer.map { $0.available || !$0.groups.isEmpty ? $0.groups : [] } ?? []
    }
}
