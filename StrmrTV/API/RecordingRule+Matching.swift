import Foundation

/// Which guide airings a rule covers, mirroring the server's rule expansion
/// (`services/recordings`: `ruleMatchesChannel`, `matchesRecordingRule`, `normalizeRecordingTitle`),
/// so the guide can offer to cancel or switch the series a programme already belongs to.
extension RecordingRule {
    func covers(title: String, on channel: LiveChannel) -> Bool {
        let onChannel = allChannels
            || (channelId?.isEmpty == false && channelId?.caseInsensitiveCompare(channel.id) == .orderedSame)
            || (tvgId?.isEmpty == false && channel.tvgId.map { tvgId?.caseInsensitiveCompare($0) == .orderedSame } == true)
        guard onChannel else { return false }
        if isRegex {
            // The server prefixes (?i); an explicit (?-i) in the pattern still wins.
            guard let regex = try? NSRegularExpression(pattern: "(?i)" + pattern) else { return false }
            return regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
        }
        return Self.normalizedTitle(pattern) == Self.normalizedTitle(title)
    }

    /// Lower-cased letters and digits, every other run collapsed to one space (the server's
    /// `normalizeRecordingTitle`).
    static func normalizedTitle(_ value: String) -> String {
        var out = ""
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if !out.isEmpty, !out.hasSuffix(" ") {
                out.append(" ")
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// "“Pattern” on Channel" / "“Pattern” on all channels", for confirmations and notices.
    var summary: String {
        let scope = allChannels ? String(localized: "all channels") : (channelName ?? String(localized: "this channel"))
        return String(localized: "“\(pattern)” on \(scope)")
    }
}
