#if DEBUG
import Foundation

/// Debug builds only: `/api/sports/…` answers read from a folder of JSON files instead of the
/// server, so every sport's views can be checked on screen out of season (as the Expo app's
/// `*.local` preview routes do). A request maps to `<folder>/<path after /api/sports/>.json`
/// (`game/401873010.json`, `scoreboard.json`; the query is ignored) and goes to the server when
/// there is no such file. Turn it on with
/// `xcrun simctl spawn booted defaults write com.strmr.app.nx StrmrSportsFixtures <folder>` and
/// off with `defaults delete`; `scripts/sports-fixtures.py` builds a folder from the Expo fixtures.
enum SportsFixtures {
    private static let prefix = "/api/sports/"

    static func response(path: String) -> Data? {
        guard path.hasPrefix(prefix),
              let folder = UserDefaults.standard.string(forKey: "StrmrSportsFixtures"), !folder.isEmpty,
              let relative = String(path.dropFirst(prefix.count)).removingPercentEncoding,
              !relative.isEmpty, !relative.contains("..") else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: folder).appendingPathComponent(relative + ".json"))
    }
}
#endif
