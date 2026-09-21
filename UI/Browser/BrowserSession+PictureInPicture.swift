//
//  BrowserSession+PictureInPicture.swift
//  Luna
//
//  §3.2's Automatic Picture-In-Picture, at the one seam that knows which tab
//  is on screen.
//
//  The mechanism is `TabController`'s; what belongs here is the pair of
//  questions it cannot answer — which tab was just left, and whether the site
//  it belongs to has the permission. Both are per-site, so a user who wants
//  YouTube to float and everything else to stay put gets exactly that.
//
//  Not driven from `activateTab`. Switching Space assigns `activeSpaceID`
//  before it activates that Space's remembered tab, so by the time the
//  activation runs the tab being left is no longer derivable from the session's
//  own state. `presentedTabID` is the honest record of what has been on screen,
//  and `notifyChange()` is where it is kept — one place, running after every
//  move the selection can make and before anybody is told about it.
//

import AppKit
import BrowserKit

extension BrowserSession {

    /// Tells the tab leaving the screen to float its video, and the one arriving
    /// to take its own back. A no-op when nothing changed, which is most calls:
    /// this runs on every structural change and almost none of them move the
    /// selection.
    func handOffPictureInPicture(to id: UUID?) {
        guard presentedTabID != id else { return }
        let leaving = presentedTabID
        presentedTabID = id
        if let leaving, allowsAutomaticPictureInPicture(leaving) {
            controller(for: leaving)?.enterAutomaticPictureInPicture()
        }
        // Coming back always puts the video into the page, whatever the
        // permission says: a floating window the user cannot get rid of by
        // returning to the tab it came from is a worse bug than no PiP at all.
        if let id { controller(for: id)?.leaveAutomaticPictureInPicture() }
    }

    private func allowsAutomaticPictureInPicture(_ id: UUID) -> Bool {
        SitePermissions.shared.isAllowed(
            .automaticPictureInPicture,
            forHost: tab(id)?.url.host(percentEncoded: false)
        )
    }
}
