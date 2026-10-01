//
//  BrowserSession+NowPlaying.swift
//  Luna
//
//  §18.4a: the Mac's play/pause keys and Now Playing. WebKit does both
//  itself — the last page to play audibly registers with the system on
//  Luna's behalf, and a key press goes to that page's process. Luna's part
//  is keeping that page there to answer: it is the tab the user expects the
//  key to reach, and §19.2's sweep put it to sleep once it was paused,
//  because a paused tab is not an audible one.
//
//  The other half, a page that is there but asleep, is
//  `WebViewFactory.makeConfiguration`'s scheduling policy.
//

import BrowserKit
import Foundation

extension BrowserSession {

    /// Hands Now Playing to a tab that has just become audible, and takes it
    /// back from one whose document no longer has played anything — a new
    /// page, or a tab gone cold.
    func noteNowPlaying(_ id: UUID, _ state: TabState) {
        if state.isPlayingAudio {
            nowPlayingTabID = id
        } else if nowPlayingTabID == id, !state.hasPlayedAudio {
            nowPlayingTabID = nil
        }
    }
}
