//
//  BrowserCommands+Develop.swift
//  Luna
//
//  The Develop menu's commands (docs/SETTINGS-SPEC.md §3.9). The inspector
//  itself is WebKit's and is reached through `WebInspector`, the one written
//  exception to D10; everything else here is public API.
//

import AppKit
import BrowserKit
import WebKit

/// Whether the menu bar carries Develop. A setting, like Safari's, and on by
/// default: the inspector is only useful to someone who can find it.
@MainActor
enum DevelopMenu {

    static let key = "advanced.showDevelopMenu"

    static var isShown: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            (NSApp.delegate as? AppDelegate)?.shortcutsDidChange()
        }
    }
}

extension AppDelegate {

    private var activeWebView: WKWebView? { session?.activeController?.webView }

    /// `⌥⌘I`, and the same key closes it again, as Safari's does.
    @objc func toggleWebInspector(_ sender: Any?) {
        if WebInspector.isVisible(for: activeWebView) {
            WebInspector.close(for: activeWebView)
        } else {
            WebInspector.show(.elements, for: activeWebView)
        }
    }

    @objc func showJavaScriptConsole(_ sender: Any?) {
        WebInspector.show(.console, for: activeWebView)
    }

    @objc func showPageSource(_ sender: Any?) {
        WebInspector.show(.sources, for: activeWebView)
    }

    @objc func startElementSelection(_ sender: Any?) {
        WebInspector.toggleElementSelection(for: activeWebView)
    }

    /// Every tab, not just this one, as Safari's switch does, and the page in
    /// front reloads so the change is visible at once. Other tabs pick it up
    /// on their next load.
    @objc func toggleJavaScript(_ sender: Any?) {
        WebViewFactory.isPageJavaScriptDisabled.toggle()
        activeWebView?.reload()
        PageToast.javaScript(disabled: WebViewFactory.isPageJavaScriptDisabled).show(in: session?.hostWindow)
    }

    @objc func emptyCaches(_ sender: Any?) {
        let privateStores = windows.map(\.session)
            .filter(\.isPrivate)
            .flatMap { session in
                session.allTabs(includeArchived: false).compactMap { session.controller(for: $0.id)?.webView }
            }
            .map(\.configuration.websiteDataStore)
        let window = session?.hostWindow
        Task {
            await WebsiteCaches.emptyAll(alsoIn: privateStores)
            PageToast.cachesEmptied.show(in: window)
        }
    }

    /// The Settings ▸ Advanced popup, from the menu. Takes effect on the next
    /// load, so the page in front is reloaded to show it.
    @objc func chooseUserAgent(_ sender: NSMenuItem) {
        let modes = WebViewFactory.UserAgentMode.allCases
        guard modes.indices.contains(sender.tag) else { return }
        WebViewFactory.userAgentMode = modes[sender.tag]
        for window in windows {
            for tab in window.session.allTabs(includeArchived: false) {
                guard let webView = window.session.controller(for: tab.id)?.webView else { continue }
                WebViewFactory.applyAdvancedSettings(to: webView)
            }
        }
        activeWebView?.reload()
        PageToast.userAgent(sender.title).show(in: session?.hostWindow)
    }

    /// The commands declared in this file; nil for anything else, so
    /// `validateMenuItem`'s chain carries on past it.
    func validateDevelopCommand(_ item: NSMenuItem, in session: BrowserSession) -> Bool? {
        let webView = session.activeController?.webView
        switch item.action {
        case #selector(toggleWebInspector(_:)):
            let visible = WebInspector.isVisible(for: webView)
            item.title = visible ? String(localized: "Close Web Inspector") : BrowserCommand.showWebInspector.title
            return WebInspector.isAvailable(for: webView)
        case #selector(showJavaScriptConsole(_:)), #selector(showPageSource(_:)), #selector(startElementSelection(_:)):
            return WebInspector.isAvailable(for: webView)
        case #selector(toggleJavaScript(_:)):
            item.state = WebViewFactory.isPageJavaScriptDisabled ? .on : .off
            return true
        case #selector(chooseUserAgent(_:)):
            let modes = WebViewFactory.UserAgentMode.allCases
            item.state = modes.firstIndex(of: WebViewFactory.userAgentMode) == item.tag ? .on : .off
            return true
        case #selector(emptyCaches(_:)):
            return true
        default:
            return nil
        }
    }
}
