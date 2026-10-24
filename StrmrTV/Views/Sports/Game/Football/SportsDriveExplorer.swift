import Foundation

/// The Drives tab's list and choice: both sides' drives or one side's, newest first, numbered
/// in game order. The chosen drive stays chosen while it is listed; otherwise the drive in
/// progress, else the newest one listed.
struct SportsDriveExplorer: Equatable {
    /// In game order, as the feed sends them.
    let drives: [SportsFootballDrive]
    /// The side shown; nil for both.
    var teamID: String?
    var chosenID: String?
    /// The drive in progress, chosen when nothing else is.
    var currentID: String?

    /// The drives listed, newest first.
    var listed: [SportsFootballDrive] {
        drives.filter { teamID == nil || $0.teamId == teamID }.reversed()
    }

    var selected: SportsFootballDrive? {
        let listed = listed
        return listed.first { $0.id == chosenID } ?? listed.first { $0.id == currentID } ?? listed.first
    }

    /// A drive's number in the game, from 1 (Expo numbers drives by their place in the feed).
    func number(of drive: SportsFootballDrive) -> Int { Self.number(of: drive, in: drives) }

    static func number(of drive: SportsFootballDrive, in drives: [SportsFootballDrive]) -> Int {
        (drives.firstIndex { $0.id == drive.id } ?? drives.count) + 1
    }

    /// The plays drawn as lanes on the chosen drive's field: snaps with both ends placed, the
    /// latest `limit` of them.
    static func lanes(_ plays: [SportsFootballPlay], limit: Int = 16) -> [SportsFootballPlay] {
        Array(plays.filter { SportsFootballPlayInfo.isFieldPlay($0) && SportsFootballYards.isValid($0.start)
            && SportsFootballYards.isValid($0.end) }.suffix(limit))
    }
}
