//
//  SitePermissions+SiteSettings.swift
//  BrowserKit
//
//  The per-site choices that are not permissions: §18.2's zoom. They hold in
//  every Space, so a Space's instance reads and writes the app's; a private
//  window keeps its own and reads the app's underneath them (§5.6).
//

import Foundation

extension SitePermissions {

    /// The zoom chosen for this site, or nil when it has none and shows at 100 %.
    public func zoom(forHost host: String?) -> Double? {
        guard let host = ContentBlocker.normalise(host) else { return nil }
        switch role {
        case .app: return zooms[host]
        case let .space(_, app): return app.zoom(forHost: host)
        case let .privateWindow(app): return zooms[host] ?? app.zoom(forHost: host)
        }
    }

    /// Nil, or 1, forgets it: 100 % is what every site shows without one.
    ///
    /// A private window's zoom stays in the window. Clearing one there stores an
    /// explicit 1, so the app's zoom for the site does not show through it.
    public func setZoom(_ zoom: Double?, forHost host: String) {
        guard let host = ContentBlocker.normalise(host) else { return }
        let zoom = zoom == 1 ? nil : zoom
        switch role {
        case .app:
            zooms[host] = zoom
            let store = store
            Task { try? await store?.setSiteZoom(zoom, host: host) }
        case let .space(_, app):
            app.setZoom(zoom, forHost: host)
        case .privateWindow:
            zooms[host] = zoom ?? 1
        }
    }
}
