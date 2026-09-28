//
//  LunaWebView.swift
//  Luna
//
//  Every page's web view, for the one thing `WKWebView` leaves to AppKit:
//  the page's right-click menu. BrowserKit builds the views through
//  `WebViewFactory.makeView`, which launch points here.
//

import AppKit
import BrowserKit
import WebKit

@MainActor
final class LunaWebView: WKWebView {

    /// WebKit's own item. There is no public way to learn which link was
    /// right-clicked, so Open Link in New Tab sends this one and marks the tab
    /// it makes as a background one (`TabController.nextNewTabIsBackground`).
    static let newWindowItem = "WKMenuItemIdentifierOpenLinkInNewWindow"

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let newWindow = menu.items.first(where: { $0.identifier?.rawValue == Self.newWindowItem }),
              newWindow.action != nil else { return }
        let item = NSMenuItem(
            title: String(localized: "Open Link in New Tab"), action: #selector(openLinkInNewTab(_:)), keyEquivalent: ""
        )
        item.target = self
        item.representedObject = newWindow
        menu.insertItem(item, at: menu.index(of: newWindow))
    }

    @objc private func openLinkInNewTab(_ sender: NSMenuItem) {
        guard let newWindow = sender.representedObject as? NSMenuItem, let action = newWindow.action else { return }
        (uiDelegate as? TabController)?.nextNewTabIsBackground = true
        NSApp.sendAction(action, to: newWindow.target, from: newWindow)
    }
}
