import Foundation
import Testing
import WebKit
@testable import BrowserKit

/// §18.4a: the page the play/pause keys reach stays there to answer them —
/// awake through §19.2's sweep, and running rather than suspended once it
/// has left the window.
@Suite("Now Playing (§18.4a)")
@MainActor
struct NowPlayingTests {

    private let policy = HibernationPolicy(liveBudget: 1, idleThreshold: 60, pressureBudget: 1)
    private let now = Date()

    /// Three tabs, all idle past the threshold; the first is active and the
    /// third holds Now Playing.
    private func tabs() -> ([TabActivity], [UUID]) {
        let ids = (0..<3).map { _ in UUID() }
        let live = ids.enumerated().map { index, id in
            TabActivity(id: id, lastActiveAt: now.addingTimeInterval(-600), holdsNowPlaying: index == 2)
        }
        return (live, ids)
    }

    @Test func thePausedTabThatLastPlayedIsNotPutToSleep() {
        let (live, ids) = tabs()
        let doomed = policy.tabsToHibernate(live: live, mru: ids, activeID: ids[0], now: now)
        #expect(doomed == [ids[1]])
    }

    @Test func itOutlastsAMemoryWarningButNotACriticalOne() {
        let (live, ids) = tabs()
        let warned = policy.tabsToHibernate(live: live, mru: ids, activeID: ids[0], now: now, pressure: .warning)
        #expect(!warned.contains(ids[2]))
        let critical = policy.tabsToHibernate(live: live, mru: ids, activeID: ids[0], now: now, pressure: .critical)
        #expect(critical.contains(ids[2]))
    }

    /// Only throttled: the measurement is in `makeConfiguration`.
    @Test func aTabLeftInTheBackgroundIsThrottledNotSuspended() {
        let configuration = WebViewFactory.makeConfiguration(dataStore: .nonPersistent())
        #expect(configuration.preferences.inactiveSchedulingPolicy == .throttle)
    }

    /// A document that has made a sound keeps saying so after it pauses, and a
    /// new document starts without it.
    @Test func aTabRemembersItPlayedUntilItsNextPage() throws {
        let controller = TabController(id: UUID(), dataStore: .nonPersistent())
        controller.activate()
        controller.playedAudio = true
        controller.publishState()
        #expect(controller.state.hasPlayedAudio)
        #expect(!controller.state.isPlayingAudio)

        controller.resetPerDocumentState()
        controller.publishState()
        #expect(!controller.state.hasPlayedAudio)

        controller.playedAudio = true
        controller.hibernate()
        #expect(!controller.state.hasPlayedAudio, "a cold tab cannot answer the keys")
    }
}
