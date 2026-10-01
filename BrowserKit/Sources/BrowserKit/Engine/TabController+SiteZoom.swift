//
//  TabController+SiteZoom.swift
//  BrowserKit
//
//  §18.2: each document opens at its site's zoom. `pageZoom` belongs to the
//  web view, not the document, so without this a zoomed site's zoom would
//  follow the tab to the next site it visits.
//

import WebKit

public extension TabController {

    /// Called at `didCommit`: the new document exists and has not painted, so
    /// it never shows at the last site's zoom.
    func applySiteZoom() {
        guard let webView else { return }
        let zoom = CGFloat(sitePermissions.zoom(forHost: webView.url?.host(percentEncoded: false)) ?? 1)
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
    }
}
