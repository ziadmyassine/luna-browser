import Foundation
import WebKit

/// WebKit's own Web Inspector, opened from inside Luna rather than from
/// Safari's Develop menu.
///
/// Every call here is SPI, and this file is the written exception to D10
/// (docs/DECISIONS.md). The public `isInspectable` only lets another app attach:
/// measured on macOS 27, it adds nothing to the page's right-click menu and
/// offers no way to open the inspector. Each selector is checked before it
/// is sent, so a WebKit that drops one loses the command, not the app.
@MainActor
public enum WebInspector {

    /// Where the inspector opens, the three places Safari's Develop menu goes.
    public enum Panel {
        case elements, console, sources
    }

    /// `developerExtrasEnabled` is what puts Inspect Element in the page's
    /// right-click menu. It lives on the preferences object the web view
    /// shares with its configuration, so it takes effect on a live page.
    static func setDeveloperExtras(_ on: Bool, on webView: WKWebView) {
        let preferences = webView.configuration.preferences
        guard preferences.responds(to: NSSelectorFromString("_setDeveloperExtrasEnabled:")) else { return }
        preferences.setValue(on, forKey: "developerExtrasEnabled")
    }

    /// Whether the inspector can be opened for `webView` at all: the setting is
    /// on and this WebKit still has the calls.
    public static func isAvailable(for webView: WKWebView?) -> Bool {
        guard WebViewFactory.isWebInspectorEnabled, let webView else { return false }
        return inspector(of: webView) != nil
    }

    public static func isVisible(for webView: WKWebView?) -> Bool {
        guard let webView, let inspector = inspector(of: webView),
              inspector.responds(to: NSSelectorFromString("isVisible")) else { return false }
        return inspector.value(forKey: "visible") as? Bool ?? false
    }

    public static func show(_ panel: Panel, for webView: WKWebView?) {
        guard isAvailable(for: webView), let webView else { return }
        let selector = switch panel {
        case .elements: "show"
        case .console: "showConsole"
        case .sources: "showResources"
        }
        send(selector, to: webView)
    }

    public static func close(for webView: WKWebView?) {
        guard let webView else { return }
        send("close", to: webView)
    }

    /// The pointer picks an element on the page and the inspector jumps to it.
    /// The inspector is opened first: selection with nothing to show it in
    /// does nothing.
    public static func toggleElementSelection(for webView: WKWebView?) {
        guard isAvailable(for: webView), let webView else { return }
        if !isVisible(for: webView) { send("show", to: webView) }
        send("toggleElementSelection", to: webView)
    }

    private static func inspector(of webView: WKWebView) -> NSObject? {
        let getter = NSSelectorFromString("_inspector")
        guard webView.responds(to: getter) else { return nil }
        return webView.perform(getter)?.takeUnretainedValue() as? NSObject
    }

    private static func send(_ name: String, to webView: WKWebView) {
        let selector = NSSelectorFromString(name)
        guard let inspector = inspector(of: webView), inspector.responds(to: selector) else { return }
        inspector.perform(selector)
    }
}

/// Safari's Develop ▸ Empty Caches: every profile's HTTP caches, and nothing
/// else — cookies, storage and history stay.
public enum WebsiteCaches {

    public static let types: Set<String> = [
        WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache
    ]

    /// Every identified store on disk, including profiles with no tab awake,
    /// plus `extra`: a private window's stores have no identifier to list.
    @MainActor
    public static func emptyAll(alsoIn extra: [WKWebsiteDataStore] = []) async {
        var stores = extra
        for identifier in await WKWebsiteDataStore.allDataStoreIdentifiers {
            stores.append(WKWebsiteDataStore(forIdentifier: identifier))
        }
        stores.append(.default())
        for store in stores {
            await store.removeData(ofTypes: types, modifiedSince: .distantPast)
        }
    }
}
