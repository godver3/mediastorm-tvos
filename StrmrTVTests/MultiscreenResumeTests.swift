import XCTest
@testable import StrmrTV

/// Resume Multiscreen's device-local store: the last selection per profile, and the load
/// warning that shows once.
@MainActor
final class MultiscreenResumeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var profile = "p1"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "MultiscreenResumeTests")
        defaults.removePersistentDomain(forName: "MultiscreenResumeTests")
    }

    private func store() -> MultiscreenResume {
        MultiscreenResume(defaults: defaults, profile: { [unowned self] in profile })
    }

    private static func channel(_ id: String) -> LiveChannel {
        LiveChannel(id: id, name: id.uppercased(), url: "http://provider/\(id)", logo: "http://logo/\(id)", group: "News",
                    tvgId: "\(id).tv", tvgName: nil, sourceId: "a", sourceName: "A", playbackId: "pb-\(id)")
    }

    func testSavedSelectionRoundTripsWithEveryTuningField() {
        let selection = MultiscreenResume.Selection(channels: [Self.channel("a"), Self.channel("b"), Self.channel("c")],
                                                    audioIndex: 2)
        store().save(selection)
        // A fresh store reads it back from the device, as after a relaunch.
        XCTAssertEqual(store().saved, selection)
        XCTAssertEqual(store().saved?.channels.first?.playbackId, "pb-a")
        XCTAssertEqual(store().saved?.channels.first?.tvgId, "a.tv")
    }

    func testFewerThanTwoChannelsKeepTheEarlierSelection() {
        let pair = MultiscreenResume.Selection(channels: [Self.channel("a"), Self.channel("b")], audioIndex: 0)
        let resume = store()
        resume.save(pair)
        resume.save(.init(channels: [Self.channel("c")], audioIndex: 0))
        XCTAssertEqual(resume.saved, pair)
    }

    func testNothingSavedOffersNoResume() {
        XCTAssertNil(store().saved)
    }

    func testSelectionsArePerProfile() {
        let resume = store()
        resume.save(.init(channels: [Self.channel("a"), Self.channel("b")], audioIndex: 1))
        profile = "p2"
        XCTAssertNil(resume.saved)
        profile = "p1"
        XCTAssertEqual(resume.saved?.audioIndex, 1)
    }

    func testSaveBumpsRevisionOnlyOnChange() {
        let resume = store()
        let pair = MultiscreenResume.Selection(channels: [Self.channel("a"), Self.channel("b")], audioIndex: 0)
        resume.save(pair)
        resume.save(pair)
        XCTAssertEqual(resume.revision, 1)
    }

    func testWarningShownPersistsOnTheDevice() {
        XCTAssertFalse(store().warningShown)
        let resume = store()
        resume.warningShown = true
        XCTAssertTrue(store().warningShown)
    }
}
