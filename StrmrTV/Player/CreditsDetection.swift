import Foundation

/// The decision side of on-device credits detection, as the Expo player's detector decides it:
/// past 90 % of the runtime a frame is read every 5 s, then every second once credit-like text
/// shows; three such samples in a row, at least four different lines between them and not all
/// alike (credits roll, a title card doesn't) mark the credits, starting at the window's first
/// sample. Fires once. No Vision or engine here, so it is testable on its own.
struct CreditsDetection {
    static let startFraction = 0.9
    static let coarseInterval: Double = 5
    static let fineInterval: Double = 1
    static let windowSize = 3
    static let minStringsPerSample = 2
    static let minUniqueStrings = 4

    private struct Sample {
        let time: Double
        let strings: Set<String>
    }

    private var samples: [Sample] = []
    private var lastSampleTime: Double?
    /// Where the credits start, once found.
    private(set) var detectedStart: Double?
    /// A frame is being read or recognised; no other starts until it finishes.
    private(set) var inFlight = false

    /// Credit-like text was in the last sample, so the next comes after a second, not five.
    var isFine: Bool { !samples.isEmpty }

    /// Whether to read a frame at `time`; when true a sample is in flight until `record` or `skip`.
    mutating func shouldSample(at time: Double, duration: Double) -> Bool {
        guard detectedStart == nil, !inFlight, duration > 0, time.isFinite,
              time / duration >= Self.startFraction else { return false }
        if let last = lastSampleTime {
            // A seek either way breaks the run of consecutive samples.
            if time < last || time - last > Self.coarseInterval * 2 {
                samples.removeAll()
                lastSampleTime = nil
            } else if time - last < (isFine ? Self.fineInterval : Self.coarseInterval) {
                return false
            }
        }
        inFlight = true
        lastSampleTime = time
        return true
    }

    /// No frame at hand (nothing resident there, or the read was dropped): try again at the next interval.
    mutating func skip() {
        inFlight = false
    }

    /// The text read from the frame shown at `time`. Returns the credits' start the one time they are found.
    mutating func record(_ recognized: [String], at time: Double) -> Double? {
        inFlight = false
        guard detectedStart == nil else { return nil }
        let strings = Self.creditStrings(recognized)
        guard strings.count >= Self.minStringsPerSample else {
            samples.removeAll()
            return nil
        }
        // The same picture again (a held card, or the same keyframe) adds nothing.
        if samples.last?.strings == strings { return nil }
        samples.append(Sample(time: time, strings: strings))
        if samples.count > Self.windowSize { samples.removeFirst(samples.count - Self.windowSize) }
        guard samples.count >= Self.windowSize,
              samples.allSatisfy({ $0.strings.count >= Self.minStringsPerSample }),
              Set(samples.flatMap(\.strings)).count >= Self.minUniqueStrings,
              Set(samples.map(\.strings)).count > 1 else { return nil }
        let start = samples[0].time
        detectedStart = start
        return start
    }

    // MARK: Text

    /// The recognised lines that look like credits, normalised.
    static func creditStrings(_ lines: [String]) -> Set<String> {
        Set(lines.map(normalize).filter(looksLikeCredit))
    }

    /// Lower case, punctuation to spaces, whitespace collapsed.
    static func normalize(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespaces.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A name, a role or a company: short and mostly letters. Not dialogue (long) nor numbers.
    static func looksLikeCredit(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...60).contains(trimmed.count) else { return false }
        let letters = trimmed.filter { $0.isLetter || $0 == " " || $0 == "." || $0 == "-" || $0 == "'" }.count
        return Double(letters) / Double(trimmed.count) > 0.7
    }
}
