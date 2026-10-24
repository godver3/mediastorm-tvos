import Foundation

/// A basketball game's clock as elapsed seconds (Expo `basketballElapsed` and the regulation of
/// `basketballLeadGeometry`): four 12-minute NBA quarters, two 20-minute men's college halves, four
/// 10-minute quarters for the WNBA and women's college, then 5-minute overtimes.
struct SportsGameClock: Equatable {
    let periods: Int
    let seconds: Double

    /// The win-probability chart's clock: any league, NBA and men's college by their own lengths.
    init(league: String) {
        periods = league == "mens-college-basketball" ? 2 : 4
        seconds = league == "nba" ? 720 : periods == 2 ? 1200 : 600
    }

    /// The lead chart's clock: the four basketball leagues only.
    init?(basketball league: String) {
        guard ["nba", "wnba", "mens-college-basketball", "womens-college-basketball"].contains(league) else { return nil }
        self.init(league: league)
    }

    func length(_ period: Int) -> Double { period > periods ? 300 : seconds }

    /// When a period starts.
    func start(_ period: Int) -> Double {
        Double(min(period - 1, periods)) * seconds + Double(max(0, period - 1 - periods)) * 300
    }

    /// Seconds played at a period's clock ("7:21", "16.9", "0.0"); nil for a malformed clock.
    func elapsed(period: Int, clock: String) -> Double? {
        guard period >= 1, let match = clock.wholeMatch(of: #/(?:(\d+):)?(\d{1,2}(?:\.\d+)?)/#),
              let seconds = Double(match.2), seconds < 60 else { return nil }
        let remaining = Double(match.1.flatMap { Int($0) } ?? 0) * 60 + seconds
        guard remaining <= length(period) else { return nil }
        return start(period) + length(period) - remaining
    }

    /// "Q1", "H2", "OT1".
    func label(_ period: Int) -> String {
        period > periods ? "OT\(period - periods)" : "\(periods == 2 ? "H" : "Q")\(period)"
    }

    /// The period lines of a chart that runs `duration` seconds.
    func marks(through duration: Double, lastPeriod: Int) -> [SportsChartPeriod] {
        (1...max(1, lastPeriod)).map { SportsChartPeriod(start: start($0), label: label($0)) }.filter { $0.start <= duration }
    }
}

/// Where a period starts on a chart, and its short name.
struct SportsChartPeriod: Equatable, Hashable {
    let start: Double
    let label: String
}

/// ESPN's win probability over the game (Expo `SportsWinProbability`): at least two points, each
/// at a readable clock, a probability within 0…1 and in game order, else nothing is drawn.
struct SportsWinProbabilitySeries: Equatable {
    struct Point: Equatable {
        let elapsed: Double
        let home: Double
        let period: Int
        let periodLabel: String
        let clock: String
    }

    let points: [Point]
    let duration: Double
    let periods: [SportsChartPeriod]

    var latest: Point { points[points.count - 1] }

    init?(page: SportsGamePage) {
        let clock = SportsGameClock(league: page.game.league)
        var points: [Point] = []
        for sample in page.detail.winProbability {
            guard let elapsed = clock.elapsed(period: sample.period, clock: sample.clock), sample.home.isFinite,
                  (0...1).contains(sample.home), elapsed >= (points.last?.elapsed ?? 0) else { return nil }
            points.append(Point(elapsed: elapsed, home: sample.home, period: sample.period,
                                periodLabel: sample.periodLabel, clock: sample.clock))
        }
        guard points.count >= 2 else { return nil }
        self.points = points
        duration = max(1, points[points.count - 1].elapsed)
        periods = clock.marks(through: duration, lastPeriod: points[points.count - 1].period)
    }
}

/// The lead over the game (Expo `basketballLeadGeometry`): only a complete history of this game and
/// its sides, every point at a readable clock and in order, ending on the scoreboard's score;
/// otherwise nothing is drawn rather than a made-up curve. The lead is away minus home (away
/// above zero), kept where it changes.
struct SportsLeadSeries: Equatable {
    struct Point: Equatable {
        let elapsed: Double
        let lead: Double
    }

    let points: [Point]
    let duration: Double
    /// The scale either side of zero: at least 5, rounded up to tens.
    let extent: Double
    let periods: [SportsChartPeriod]

    var latest: Double { points[points.count - 1].lead }

    init?(page: SportsGamePage) {
        let game = page.game
        guard page.lifecycle != .scheduled, let history = page.detail.scoreHistory, history.complete,
              history.eventId == game.id, history.awayTeamId == game.awayTeam.id, history.homeTeamId == game.homeTeam.id,
              history.points.count >= 2, let clock = SportsGameClock(basketball: game.league) else { return nil }
        var all: [Point] = []
        for point in history.points {
            // ESPN gives seconds-only clocks inside the final minute ("23.2").
            guard point.away >= 0, point.home >= 0, point.away.isFinite, point.home.isFinite,
                  let elapsed = clock.elapsed(period: point.period, clock: point.clock),
                  elapsed >= (all.last?.elapsed ?? 0) else { return nil }
            all.append(Point(elapsed: elapsed, lead: point.away - point.home))
        }
        guard let last = history.points.last, Double(game.awayTeam.score ?? "") == last.away,
              Double(game.homeTeam.score ?? "") == last.home else { return nil }
        points = all.enumerated().filter { index, point in
            index == 0 || index == all.count - 1 || point.lead != all[index - 1].lead
        }.map(\.element)
        duration = max(1, all[all.count - 1].elapsed)
        extent = (max(5, all.map { abs($0.lead) }.max() ?? 0) / 10).rounded(.up) * 10
        periods = clock.marks(through: duration, lastPeriod: history.points[history.points.count - 1].period)
    }

    /// The curve with a point added wherever it crosses zero, so the part above zero (`max(lead, 0)`)
    /// and the part below (`min(lead, 0)`) each fill exactly to the axis in their side's colour.
    var crossings: [Point] {
        var out: [Point] = []
        for point in points {
            if let previous = out.last, previous.lead * point.lead < 0 {
                let crossing = previous.elapsed + (point.elapsed - previous.elapsed) * previous.lead / (previous.lead - point.lead)
                out.append(Point(elapsed: crossing, lead: 0))
            }
            out.append(point)
        }
        return out
    }

    /// The line in stretches on one side of zero (`away` true above, nil for a tied stretch), each
    /// drawn in that side's colour.
    var runs: [(away: Bool?, points: [Point])] {
        let curve = crossings
        var runs: [(away: Bool?, points: [Point])] = []
        for (a, b) in zip(curve, curve.dropFirst()) {
            let sum = a.lead + b.lead
            let side: Bool? = sum > 0 ? true : sum < 0 ? false : nil
            if let last = runs.last, last.away == side {
                runs[runs.count - 1].points.append(b)
            } else {
                runs.append((side, [a, b]))
            }
        }
        return runs
    }
}

extension SportsTeamColors {
    /// Chart colours (Expo `basketballChartColors`): each side's colour, else its alternate, that
    /// reads on the dark chart (contrast 3 against #101417), else light grey; then kept apart.
    static func chartPair(away: SportsTeam, home: SportsTeam) -> Pair {
        func visible(_ candidates: [String?]) -> String {
            for candidate in candidates {
                guard let hex = candidate.map({ "#" + $0.replacingOccurrences(of: "#", with: "").lowercased() }),
                      hex.count == 7, UInt32(hex.dropFirst(), radix: 16) != nil else { continue }
                if contrast(hex, "#101417") >= 3 { return hex }
            }
            return "#d0d8df"
        }
        return hexPair(away: visible([away.color, away.alternateColor]), home: visible([home.color, home.alternateColor]),
                       awayAlternate: visible([away.alternateColor]), homeAlternate: visible([home.alternateColor]))
    }
}
