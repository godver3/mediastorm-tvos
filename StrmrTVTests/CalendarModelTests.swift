import XCTest
@testable import StrmrTV

/// The Expo Calendar's model (`components/calendar/calendar-model.ts`, its tests in
/// `__tests__/calendar-model.test.ts`), the detail panel's merge
/// (`useCalendarItemDetails.ts`) and the timeline's geometry (`CalendarDateTimeline.tsx`).
final class CalendarModelTests: XCTestCase {
    private func item(_ overrides: [String: Any] = [:]) -> CalendarItem {
        var json: [String: Any] = [
            "title": "Strange New Worlds", "mediaType": "series", "seasonNumber": 4, "episodeNumber": 5,
            "airDate": "2026-09-03", "source": "watchlist", "externalIds": ["tmdb": "103516", "tvdb": "382389"],
        ]
        json.merge(overrides) { $1 }
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(CalendarItem.self, from: data)
    }

    private func movie(_ overrides: [String: Any] = [:]) -> CalendarItem {
        item(["title": "Dune", "mediaType": "movie", "seasonNumber": 0, "episodeNumber": 0,
              "externalIds": ["tmdb": "438631"]].merging(overrides) { $1 })
    }

    // MARK: Grouping

    func testGroupsChronologicallyAndFiltersUpcoming() {
        let days = CalendarModel.groupDays([item(["airDate": "2099-09-04"]), item(["airDate": "2099-09-03", "episodeNumber": 4])],
                                           filter: .upcoming, todayKey: "2099-09-01")
        XCTAssertEqual(days.map(\.key), ["2099-09-03", "2099-09-04"])
    }

    func testFiltersRecentSeriesAndMovies() {
        let items = [item(["airDate": "2026-08-30"]), movie(["airDate": "2026-09-02"]), item(["airDate": "2026-09-01", "episodeNumber": 6])]
        let today = "2026-09-01"
        XCTAssertEqual(CalendarModel.groupDays(items, filter: .recent, todayKey: today).map(\.key), ["2026-08-30"])
        XCTAssertEqual(CalendarModel.groupDays(items, filter: .upcoming, todayKey: today).map(\.key), ["2026-09-01", "2026-09-02"])
        XCTAssertEqual(CalendarModel.groupDays(items, filter: .movies, todayKey: today).map(\.key), ["2026-09-02"])
        XCTAssertEqual(CalendarModel.groupDays(items, filter: .series, todayKey: today).map(\.key), ["2026-08-30", "2026-09-01"])
    }

    func testOrdersADayByAirTimeWithAllDayLastAndTiesInServerOrder() {
        let items = [
            item(["episodeNumber": 1]),
            item(["episodeNumber": 2, "airTime": "21:00"]),
            item(["episodeNumber": 3, "airTime": "09:30"]),
            item(["episodeNumber": 4]),
        ]
        let days = CalendarModel.groupDays(items, filter: .all, todayKey: "2026-09-01")
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].items.map(\.episodeNumber), [3, 2, 1, 4])
    }

    func testDropsItemsWithoutAnAirDate() {
        XCTAssertTrue(CalendarModel.groupDays([item(["airDate": ""])], filter: .all, todayKey: "2026-09-01").isEmpty)
    }

    func testCreatesDistinctStableKeysForTwoEpisodesOfOneTitle() {
        XCTAssertNotEqual(CalendarModel.itemKey(item(["episodeNumber": 5])), CalendarModel.itemKey(item(["episodeNumber": 6])))
        XCTAssertEqual(CalendarModel.itemKey(item()), "tmdb:103516:series:2026-09-03:4:5:")
        XCTAssertEqual(CalendarModel.itemKey(item(["externalIds": ["imdb": "tt1"]])), "tt1:series:2026-09-03:4:5:")
        XCTAssertEqual(CalendarModel.itemKey(item(["externalIds": [String: String](), "title": " Foo Bar "])),
                       "foo bar:series:2026-09-03:4:5:")
    }

    // MARK: Selection

    func testFallsBackToTheFirstItemOfTheFirstRemainingDay() {
        let days = CalendarModel.groupDays([item()], filter: .all, todayKey: "2026-09-01")
        let selection = CalendarModel.resolveSelection(days, dateKey: "missing-day", itemKey: "missing-item", todayKey: "2026-09-01")
        XCTAssertEqual(selection, CalendarSelection(dateKey: "2026-09-03", itemKey: CalendarModel.itemKey(days[0].items[0])))
    }

    func testKeepsTheActiveDayAndPicksItsFirstItemWhenTheItemDisappears() {
        let days = CalendarModel.groupDays([item(["airDate": "2026-09-02", "episodeNumber": 1]), item(["episodeNumber": 6])],
                                           filter: .all, todayKey: "2026-09-01")
        let selection = CalendarModel.resolveSelection(days, dateKey: "2026-09-03", itemKey: "missing-item", todayKey: "2026-09-01")
        XCTAssertEqual(selection, CalendarSelection(dateKey: "2026-09-03", itemKey: CalendarModel.itemKey(days[1].items[0])))
    }

    func testKeepsAStillListedSelection() {
        let second = item(["episodeNumber": 6])
        let days = CalendarModel.groupDays([item(), second], filter: .all, todayKey: "2026-09-01")
        let key = CalendarModel.itemKey(second)
        XCTAssertEqual(CalendarModel.resolveSelection(days, dateKey: "2026-09-03", itemKey: key, todayKey: "2026-09-01").itemKey, key)
    }

    func testDefaultsToTodayWhenHistoricalReleasesAreLoaded() {
        let days = CalendarModel.groupDays([item(["airDate": "2026-08-30", "episodeNumber": 1]),
                                            item(["airDate": "2026-08-31", "episodeNumber": 2]),
                                            item(["airDate": "2026-09-02", "episodeNumber": 3])],
                                           filter: .all, todayKey: "2026-08-31")
        XCTAssertEqual(CalendarModel.resolveSelection(days, dateKey: nil, itemKey: nil, todayKey: "2026-08-31").dateKey, "2026-08-31")
    }

    func testDefaultsToTheClosestFutureReleaseWhenTodayHasNone() {
        let days = CalendarModel.groupDays([item(["airDate": "2026-08-29", "episodeNumber": 1]),
                                            item(["airDate": "2026-09-02", "episodeNumber": 2]),
                                            item(["airDate": "2026-09-05", "episodeNumber": 3])],
                                           filter: .all, todayKey: "2026-08-31")
        XCTAssertEqual(CalendarModel.resolveSelection(days, dateKey: nil, itemKey: nil, todayKey: "2026-08-31").dateKey, "2026-09-02")
    }

    func testDefaultsToTheMostRecentPastReleaseWhenNothingIsUpcoming() {
        let days = CalendarModel.groupDays([item(["airDate": "2026-08-20", "episodeNumber": 1]),
                                            item(["airDate": "2026-08-30", "episodeNumber": 2])],
                                           filter: .all, todayKey: "2026-08-31")
        XCTAssertEqual(CalendarModel.resolveSelection(days, dateKey: nil, itemKey: nil, todayKey: "2026-08-31").dateKey, "2026-08-30")
    }

    func testSelectsNothingWithoutDays() {
        XCTAssertEqual(CalendarModel.resolveSelection([], dateKey: nil, itemKey: nil, todayKey: "2026-08-31"), CalendarSelection())
    }

    // MARK: Text

    func testPreservesTheTVInitialismInMovieReleaseLabels() {
        let tv = movie(["releaseType": "tv"])
        XCTAssertEqual(CalendarModel.episodeLine(tv), "TV release")
        XCTAssertEqual(CalendarModel.posterMetadata(tv), "TV")
        XCTAssertEqual(CalendarModel.summary(tv), "TV release.")
        XCTAssertEqual(CalendarModel.posterMetadata(movie(["releaseType": "theatrical"])), "Theatrical")
        XCTAssertEqual(CalendarModel.posterMetadata(movie()), "")
        XCTAssertEqual(CalendarModel.episodeLine(movie()), "Movie release")
    }

    func testEpisodeLinesAndPosterMetadata() {
        XCTAssertEqual(CalendarModel.posterMetadata(item()), "S04E05")
        XCTAssertEqual(CalendarModel.posterMetadata(item(["episodeNumber": 0])), "Episode")
        XCTAssertEqual(CalendarModel.episodeLine(item(["episodeTitle": "Hegemony"])), "S04E05 - Hegemony")
        XCTAssertEqual(CalendarModel.episodeLabel(item()), "S4 E5")
        XCTAssertNil(CalendarModel.episodeLabel(movie()))
    }

    func testSummaryFallbacks() {
        XCTAssertEqual(CalendarModel.summary(item(["episodeOverview": " Ep. ", "overview": "Show."])), "Ep.")
        XCTAssertEqual(CalendarModel.summary(item(["overview": "Show."])), "Show.")
        XCTAssertEqual(CalendarModel.summary(item(["network": "Paramount+"])), "Airs on Paramount+.")
        XCTAssertEqual(CalendarModel.summary(movie()), "Movie release.")
        XCTAssertEqual(CalendarModel.summary(item()), "Episode details will appear when they are available.")
    }

    func testFormatsTimes() {
        XCTAssertEqual(CalendarModel.formatTime(nil), "All day")
        XCTAssertEqual(CalendarModel.formatTime("late"), "late")
        XCTAssertNotEqual(CalendarModel.formatTime("21:30"), "21:30:00")
        XCTAssertFalse(CalendarModel.formatTime("21:30").isEmpty)
    }

    func testDateKeysRoundTripInTheLocalZone() {
        XCTAssertEqual(CalendarModel.dateKey(CalendarModel.date(fromKey: "2026-03-08")), "2026-03-08")
        XCTAssertEqual(CalendarModel.dayHeading(CalendarModel.dateKey(.now)), "Today")
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        XCTAssertEqual(CalendarModel.dayHeading(CalendarModel.dateKey(tomorrow)), "Tomorrow")
    }

    // MARK: Detail

    func testDerivesTheDetailFromTheCalendarItemImmediately() {
        let detail = CalendarItemDetail(item(["runtimeMinutes": 58, "year": 2024, "genres": ["Sci-Fi"],
                                              "episodeTitle": "The Sehlat Who Ate Its Tail",
                                              "episodeOverview": "Transporter trouble."]))
        XCTAssertFalse(detail.isMovie)
        XCTAssertEqual(detail.heading, "The Sehlat Who Ate Its Tail")
        XCTAssertEqual(detail.eyebrow, "STRANGE NEW WORLDS")
        XCTAssertEqual(detail.episodeLabel, "S4 E5")
        XCTAssertEqual(detail.runtimeMinutes, 58)
        XCTAssertEqual(detail.synopsis, "Transporter trouble.")
        XCTAssertEqual(detail.genres, ["Sci-Fi"])
        XCTAssertEqual(detail.metadataLine, "S4 E5  ·  Released 2024")
    }

    func testPrefersRankedBackdropArtwork() {
        let detail = CalendarItemDetail(item(["posterUrl": "poster.jpg", "backdropUrls": ["", "ranked.jpg"],
                                              "textBackdropUrl": "text.jpg", "airTime": "21:30"]))
        XCTAssertEqual(detail.backdropURL, "ranked.jpg")
        XCTAssertNotNil(detail.airTime)
        XCTAssertEqual(CalendarItemDetail(item(["posterUrl": "poster.jpg"])).backdropURL, "poster.jpg")
        XCTAssertEqual(CalendarItemDetail(item(["backdropUrl": "b.jpg", "backdropUrls": ["r.jpg"]])).backdropURL, "b.jpg")
    }

    func testMovieDetailHasNoEyebrow() {
        let detail = CalendarItemDetail(movie(["episodeTitle": "ignored"]))
        XCTAssertNil(detail.eyebrow)
        XCTAssertEqual(detail.heading, "ignored")
    }

    func testMergeKeepsCalendarValuesWhereTheMetadataIsEmpty() {
        let base = CalendarItemDetail(item(["episodeOverview": "Calendar.", "genres": ["Sci-Fi"], "year": 2022]))
        var enrichment = CalendarEnrichment()
        enrichment.synopsis = "  "
        enrichment.certification = "TV-14"
        enrichment.cast = ["Anson Mount", "Rebecca Romijn", "Ethan Peck", "Jess Bush", "Christina Chong"]
        let merged = base.merged(enrichment)
        XCTAssertEqual(merged.synopsis, "Calendar.")
        XCTAssertEqual(merged.genres, ["Sci-Fi"])
        XCTAssertEqual(merged.metadataLine, "S4 E5  ·  Released 2022  ·  TV-14")
        XCTAssertEqual(merged.castLine, "Anson Mount  ·  Rebecca Romijn  ·  Ethan Peck  ·  Jess Bush")
    }

    func testGenreChipsKeepFourNonEmpty() {
        let detail = CalendarItemDetail(item(["genres": ["A", " ", "B", "C", "D", "E"]]))
        XCTAssertEqual(detail.genreChips, ["A", "B", "C", "D"])
    }

    // MARK: Timeline

    func testTimelineRunsFromTheMonthBeforeToTheMonthAfter() {
        let days = CalendarModel.groupDays([item(["airDate": "2026-09-03"]), item(["airDate": "2026-10-20"])],
                                           filter: .all, todayKey: "2026-09-01")
        let timeline = CalendarTimeline(days: days, spacing: 400)
        XCTAssertEqual(timeline.months.map(\.key), ["2026-08", "2026-09", "2026-10", "2026-11"])
        XCTAssertEqual(timeline.width, 1201)
        // September's dot is the second; the 1st of the month sits on it, the 30th on October's.
        XCTAssertEqual(timeline.position(of: "2026-09-01"), 400)
        XCTAssertEqual(timeline.position(of: "2026-09-30"), 800, accuracy: 0.001)
        XCTAssertEqual(timeline.position(of: "2026-10-16"), 800 + 15.0 / 30 * 400, accuracy: 0.001)
    }

    func testTimelineAcrossTheYearEnd() {
        let days = CalendarModel.groupDays([item(["airDate": "2026-12-31"])], filter: .all, todayKey: "2026-09-01")
        XCTAssertEqual(CalendarTimeline(days: days, spacing: 400).months.map(\.key), ["2026-11", "2026-12", "2027-01"])
        XCTAssertTrue(CalendarTimeline(days: [], spacing: 400).months.isEmpty)
    }
}
