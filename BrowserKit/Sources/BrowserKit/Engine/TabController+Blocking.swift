//
//  TabController+Blocking.swift
//  BrowserKit
//
//  An open tab taking up new block lists as soon as there are any. Lists are
//  attached when a tab is made and again on each navigation; a page that
//  never navigates kept the ones it opened with — measured, a web app updating
//  itself in place ran on lists a refresh had replaced and deleted, 20 times
//  slower to check each image against.
//

import Foundation
import WebKit

extension TabController {

    func followBlockingLists() {
        stopFollowingBlockingLists()
        blockingListsObserver = NotificationCenter.default.addObserver(
            forName: ContentBlocker.listsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reapplyBlockingLists() }
        }
    }

    /// Also where a tab whose web view has gone lets go, at the next change.
    func stopFollowingBlockingLists() {
        if let blockingListsObserver { NotificationCenter.default.removeObserver(blockingListsObserver) }
        blockingListsObserver = nil
    }

    /// The lists for the site on show, as its last navigation chose them.
    private func reapplyBlockingLists() {
        guard let webView else { return stopFollowingBlockingLists() }
        ContentBlocker.shared.apply(
            to: webView.configuration.userContentController, host: webView.url?.host(), scope: sitePermissions
        )
    }
}
